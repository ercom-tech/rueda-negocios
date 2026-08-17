require "test_helper"

# Entradas que la pantalla no ofrece pero que llegan igual.
#
# Los combos del encabezado viajan en campos ocultos y el tipo de pedido en un
# radio, así que basta con cambiarlos desde las herramientas del navegador. Sin
# validación, unas reventaban con un 500 —y en el modo con que corre la laptop
# ese 500 es la página de depuración de Rails servida a toda la LAN— y otras
# escribían en el ERP un dato que la pantalla nunca habría producido.
class ForgedInputTest < ActionDispatch::IntegrationTest
  setup do
    @user   = User.create!(erp_person_id: 960_001, username: "cap960", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 960_001, name: "Rueda 960", active: true)
    @client = Client.create!(erp_client_key: "C960", name: "Cliente 960")
    @other  = Client.create!(erp_client_key: "C961", name: "Cliente 961")
    login_as "cap960"
  end

  def header_params(extra = {})
    { order: { client_id: @client.id, kind: "remission" }.merge(extra) }
  end

  # --- Tipo de pedido fuera del enum --------------------------------------
  # `kind` es un enum: asignarle un valor desconocido levanta ArgumentError
  # ANTES de cualquier validación, así que no hay forma de atajarlo en el
  # modelo. Tiene que salir por el camino normal de "revisa los datos".

  test "un tipo de pedido inventado no revienta la pantalla" do
    assert_no_difference "Order.count" do
      post orders_path, params: header_params(kind: "regalo")
    end

    assert_response :unprocessable_entity
    assert_match(/Revisa los datos obligatorios/, response.body)
  end

  test "editar un pedido con un tipo inventado tampoco revienta" do
    order = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")

    patch order_path(order), params: header_params(kind: "regalo")

    assert_response :unprocessable_entity
    assert_equal "remission", order.reload.kind, "no debe quedar a medias"
  end

  # --- Perfiles del encabezado de OTRO cliente -----------------------------
  # Sin esto el pedido llegaba al ERP con el RFC de otro contribuyente, y el
  # PDF lo imprimía. Ninguna secuencia de clics lo produce, pero el valor va en
  # un campo oculto.

  test "un perfil fiscal de otro cliente no se guarda" do
    ajeno = ClientTaxProfile.create!(client: @other, rfc: "AAA010101AAA", business_name: "OTRO SA")
    cfdi  = CfdiUse.create!(code: "G01", description: "ADQUISICIÓN DE MERCANCÍAS")

    assert_no_difference "Order.count" do
      post orders_path, params: header_params(kind: "invoice", client_tax_profile_id: ajeno.id,
                                              cfdi_use_id: cfdi.id)
    end
    assert_response :unprocessable_entity
  end

  test "una sucursal de otro cliente no se guarda" do
    ajena = ClientBranch.create!(client: @other, erp_branch_id: 1, name: "MATRIZ OTRO")

    assert_no_difference "Order.count" do
      post orders_path, params: header_params(client_branch_id: ajena.id)
    end
    assert_response :unprocessable_entity
  end

  test "el perfil propio sí pasa" do
    propia = ClientBranch.create!(client: @client, erp_branch_id: 1, name: "MATRIZ")

    assert_difference "Order.count", 1 do
      post orders_path, params: header_params(client_branch_id: propia.id)
    end
  end

  # --- Monto de división fuera del catálogo --------------------------------
  # El ERP lo interpreta como "divide la factura cada $0.01" y al facturar
  # genera miles de facturas de un solo pedido. Se prueba sobre FACTURA: en una
  # remisión el campo no aplica y el encabezado ya lo pone en 0.

  def invoice_params(extra = {})
    tax  = ClientTaxProfile.create!(client: @client, rfc: "BBB020202BBB", business_name: "CLIENTE 960 SA")
    cfdi = CfdiUse.create!(code: "G03", description: "GASTOS EN GENERAL")
    header_params({ kind: "invoice", client_tax_profile_id: tax.id, cfdi_use_id: cfdi.id }.merge(extra))
  end

  test "un monto de división fuera del catálogo no se guarda" do
    DivideAmount.create!(erp_consecutive: 1, amount: 2000)

    assert_no_difference "Order.count" do
      post orders_path, params: invoice_params(dividir_facturas: "0.01")
    end
    assert_response :unprocessable_entity
  end

  test "un monto del catálogo sí pasa" do
    DivideAmount.create!(erp_consecutive: 1, amount: 2000)

    assert_difference "Order.count", 1 do
      post orders_path, params: invoice_params(dividir_facturas: "2000")
    end
  end

  # Sin catálogo sincronizado la pantalla no ofrece el campo: solo se exige 0.
  test "sin catálogo sincronizado el pedido se guarda con 0" do
    assert_difference "Order.count", 1 do
      post orders_path, params: invoice_params(dividir_facturas: "0")
    end
  end

  # --- Cantidad fuera del rango de la columna ------------------------------
  # `numeric(14,3)`: sin tope salía como ActiveRecord::RangeError, que ningún
  # rescue atrapa. Al ser un Turbo Stream, la tabla no se repintaba y el
  # capturista solo veía que "no pasó nada".

  test "una cantidad fuera de rango avisa en vez de reventar" do
    order = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    item  = order.order_items.create!(position: 1, quantity: 1, unit_price: 100,
                                      tax_rate: 16, discount_percent: 0)

    patch order_order_item_path(order, item), params: { order_item: { quantity: "999999999999" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # El aviso viaja en el stream que repinta el flash, no en flash[:alert].
    assert_match(/demasiado grande/, response.body)
    assert_equal 1, item.reload.quantity
  end
end
