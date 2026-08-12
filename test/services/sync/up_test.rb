require "test_helper"
require "webmock/minitest"

module Sync
  class UpTest < ActiveSupport::TestCase
    API = "http://api.test".freeze

    setup do
      @user    = User.create!(erp_person_id: 90092, username: "makita1", password: "x", role: "capturista", prefix: "1A")
      @round   = BusinessRound.create!(erp_round_id: 3, name: "Oaxaca", active: true)
      @sp      = Salesperson.create!(erp_salesperson_id: 168, name: "Omar")
      @client  = Client.create!(erp_client_key: "ABAISM", name: "Ismael", salesperson: @sp)
      @product = Product.create!(erp_product_id: 3, description: "Rotomartillo")

      # Remisión: el cliente no tiene perfiles, así que no exige encabezado.
      # `dividir_facturas` es campo de factura y en una remisión queda en 0.
      @order = Order.new(user: @user, business_round: @round, client: @client,
                         kind: "remission", status: "captured", local_folio: "RN-000001")
      @order.order_items.build(product: @product, quantity: 2, unit_price: 100,
                               discount_percent: 0, tax_rate: 16, code: "3", description: "Rotomartillo", unit: "PZA")
      @order.save!
    end

    test "transmite un pedido capturado y guarda el folio del ERP" do
      req = stub_request(:post, "#{API}/pedidos")
            .to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json,
                       headers: { "Content-Type" => "application/json" })

      result = Up.new(API).run!

      assert_equal 1, result[:transmitted].size
      assert_empty result[:failed]

      @order.reload
      assert_equal "1A0007", @order.erp_folio
      assert @order.transmitted?
      assert_not_nil @order.transmitted_at
      assert_requested req
    end

    test "idempotencia: no re-transmite pedidos que ya tienen folio" do
      @order.update!(erp_folio: "1A0001", transmitted_at: Time.current, status: "transmitted")

      result = Up.new(API).run!

      assert_empty result[:transmitted]
      # Sin stub: si intentara un POST, WebMock levantaría error → confirma que no hubo HTTP.
    end

    test "el payload lleva cliente, capturista, vendedor e items" do
      req = stub_request(:post, "#{API}/pedidos").with do |request|
        body = JSON.parse(request.body)
        body["clave_cliente"] == "ABAISM" &&
          body["capturista_erp_person_id"] == 90092 &&
          body["id_vendedor"] == 168 &&
          body["items"].first["id_producto"] == 3 &&
          body["items"].first["cantidad"].to_d == 2
      end.to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json)

      Up.new(API).run!
      assert_requested req
    end

    test "una factura transmite su monto de división de facturas" do
      tax  = ClientTaxProfile.create!(client: @client, rfc: "AAA010101AAA", business_name: "ISMAEL SA")
      cfdi = CfdiUse.create!(code: "G01", description: "ADQUISICIÓN DE MERCANCÍAS")
      DivideAmount.create!(erp_consecutive: 1, amount: 5000) # el monto debe estar en el catálogo
      @order.update!(kind: "invoice", client_tax_profile: tax, cfdi_use: cfdi, dividir_facturas: 5000)

      req = stub_request(:post, "#{API}/pedidos").with do |request|
        JSON.parse(request.body)["dividir_facturas"].to_d == 5000
      end.to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json)

      Up.new(API).run!
      assert_requested req
    end

    test "un fallo del ERP deja el pedido sin folio y lo reporta" do
      stub_request(:post, "#{API}/pedidos").to_return(status: 422, body: { message: "rechazado" }.to_json)

      result = Up.new(API).run!

      assert_empty result[:transmitted]
      assert_equal 1, result[:failed].size
      assert_nil @order.reload.erp_folio
      assert @order.captured?, "sigue capturado para reintentar"
    end

    test "un timeout de red marca el pedido fallido sin abortar la transmisión" do
      stub_request(:post, "#{API}/pedidos").to_timeout

      result = Up.new(API).run!

      assert_empty result[:transmitted]
      assert_equal 1, result[:failed].size
      assert_nil @order.reload.erp_folio
      assert @order.captured?
      # El panel muestra este texto: "execution expired" no le dice nada a
      # quien está operando en el salón.
      assert_match(/tardó demasiado en responder/, result[:failed].first[:error])
    end

    # Cada falla de red se traduce a algo que el operador pueda leer. El caso
    # de ActiveRecord es el que más importa: si falla ahí, el pedido YA está en
    # el ERP y lo único que no se guardó es el folio de vuelta.
    test "cada tipo de falla se traduce a un motivo legible" do
      up = Up.new(API)
      {
        ActiveRecord::StatementInvalid.new("PG::Error") => /entró al ERP pero no se pudo guardar su folio/,
        Net::ReadTimeout.new                            => /tardó demasiado en responder/,
        Errno::ECONNREFUSED.new                         => /no se pudo conectar con el servidor/,
        SocketError.new("getaddrinfo")                  => /no se pudo conectar con el servidor/,
        JSON::ParserError.new("unexpected token")       => /respondió algo que no se entiende/
      }.each do |error, expected|
        assert_match expected, up.send(:failure_reason, error), "#{error.class} sin motivo legible"
      end
    end

    test "un 200 con cuerpo no-JSON marca fallido ese pedido y sigue con el resto" do
      order2 = Order.new(user: @user, business_round: @round, client: @client,
                         kind: "remission", status: "captured", local_folio: "RN-000002")
      order2.order_items.build(product: @product, quantity: 1, unit_price: 50,
                               discount_percent: 0, tax_rate: 16, code: "3", description: "Rotomartillo", unit: "PZA")
      order2.save!

      # 1ª respuesta (para @order): HTML de proxy; 2ª (para order2): válida.
      stub_request(:post, "#{API}/pedidos")
        .to_return({ status: 200, body: "<html>gateway</html>" },
                   { status: 201, body: { clave_pedido: "1A0008" }.to_json })

      result = Up.new(API).run!

      assert_equal 1, result[:failed].size, "el pedido con respuesta rota debe fallar"
      assert_equal 1, result[:transmitted].size, "el resto del lote debe transmitirse"
      assert @order.reload.captured?, "sigue capturado para reintentar"
      assert_equal "1A0008", order2.reload.erp_folio
    end

    test "un 200 sin clave_pedido NO marca el pedido como transmitido" do
      stub_request(:post, "#{API}/pedidos")
        .to_return(status: 200, body: { idempotent: false }.to_json)

      result = Up.new(API).run!

      assert_empty result[:transmitted]
      assert_equal 1, result[:failed].size
      @order.reload
      assert @order.captured?, "sin folio no puede darse por transmitido"
      assert_nil @order.erp_folio
    end

    # --- Edición en pleno vuelo ---------------------------------------------
    # La captura se pausa mientras corre un sync, así que solo queda la ventana
    # entre esa comprobación y el commit de la edición. Si algo se cuela, el ERP
    # se queda con la versión vieja y la pantalla con la nueva: se detecta y se
    # reporta, porque en silencio no se enteraría nadie.

    test "un pedido editado durante su transmisión se reporta como conflicto" do
      # Simula la edición en el instante entre armar el payload y guardar el
      # folio: el POST ya salió con la versión anterior.
      stub_request(:post, "#{API}/pedidos").to_return do
        @order.order_items.first.update_columns(quantity: 99, updated_at: Time.current)
        @order.update_columns(updated_at: Time.current)
        { status: 201, body: { clave_pedido: "1A0007" }.to_json }
      end

      result = Up.new(API).run!

      assert_equal 1, result[:transmitted].size, "el pedido SÍ entró al ERP"
      assert_equal 1, result[:conflicts].size
      assert_equal "RN-000001", result[:conflicts].first[:local]
      assert_equal "1A0007", result[:conflicts].first[:erp]
    end

    test "una transmisión sin ediciones no reporta conflictos" do
      stub_request(:post, "#{API}/pedidos")
        .to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json)

      assert_empty Up.new(API).run![:conflicts]
    end

    # --- Remisión: a nombre de quién va -------------------------------------
    # El ERP resuelve el destinatario y la cuenta de cobranza de una remisión
    # contra el consecutivo de su perfil. El capturista lo elige en el paso 1 y
    # se quedaba en la laptop: la remisión llegaba al ERP sin destinatario.

    test "el payload de una remisión lleva a nombre de quién va" do
      profile = ClientReceiptProfile.create!(client: @client, erp_receipt_profile_id: 2, name: "SUCURSAL CENTRO")
      @order.update!(client_receipt_profile: profile)

      req = stub_request(:post, "#{API}/pedidos").with do |request|
        JSON.parse(request.body)["consec_remision"] == 2
      end.to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json)

      Up.new(API).run!
      assert_requested req
    end

    # Un pedido capturado ANTES de que el encabezado limpiara su rama inactiva
    # puede traer perfil de remisión siendo factura: no debe viajar al ERP.
    test "una factura no transmite destinatario de remisión" do
      profile = ClientReceiptProfile.create!(client: @client, erp_receipt_profile_id: 2, name: "SUCURSAL CENTRO")
      @order.update_column(:kind, "invoice")
      @order.update_column(:client_receipt_profile_id, profile.id)

      req = stub_request(:post, "#{API}/pedidos").with do |request|
        JSON.parse(request.body)["consec_remision"].nil?
      end.to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json)

      Up.new(API).run!
      assert_requested req
    end

    test "una remisión no transmite monto de división de facturas" do
      # El pedido del setup es remisión y se creó con dividir_facturas 5000
      # (fila anterior a la limpieza del encabezado): no debe viajar.
      @order.update_column(:dividir_facturas, 5000)

      req = stub_request(:post, "#{API}/pedidos").with do |request|
        JSON.parse(request.body)["dividir_facturas"].to_d.zero?
      end.to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json)

      Up.new(API).run!
      assert_requested req
    end

    test "un cliente sin perfiles de remisión transmite sin destinatario" do
      req = stub_request(:post, "#{API}/pedidos").with do |request|
        JSON.parse(request.body)["consec_remision"].nil?
      end.to_return(status: 201, body: { clave_pedido: "1A0007" }.to_json)

      Up.new(API).run!
      assert_requested req
    end

    # --- Guarda: no transmitir con pedidos en borrador ----------------------
    # El sync-up solo toma `captured`: transmitir con borradores vivos deja al
    # operador creyendo que todo llegó al ERP, y cerrar la rueda los purga.

    def draft!
      Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    end

    test "con pedidos en borrador NO transmite nada y levanta GuardError" do
      draft!
      req = stub_request(:post, "#{API}/pedidos")

      error = assert_raises(Up::GuardError) { Up.new(API).run! }

      assert_match(/Hay 1 pedido en borrador y no se transmitiría\./, error.message)
      assert_not_requested req
      assert @order.reload.captured?, "el pedido capturado sigue intacto"
    end

    test "guard! cuenta todos los borradores y no se fija en los capturados" do
      2.times { draft! }

      error = assert_raises(Up::GuardError) { Up.guard! }
      assert_match(/Hay 2 pedidos en borrador y no se transmitirían\./, error.message)
    end

    test "sin borradores la guarda deja pasar" do
      assert_nothing_raised { Up.guard! }
    end

    test "un borrador ya descartado deja de bloquear" do
      draft = draft!
      assert_raises(Up::GuardError) { Up.guard! }

      draft.destroy
      assert_nothing_raised { Up.guard! }
    end
  end
end
