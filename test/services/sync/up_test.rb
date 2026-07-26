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

    test "un fallo del ERP deja el pedido sin folio y lo reporta" do
      stub_request(:post, "#{API}/pedidos").to_return(status: 422, body: { message: "rechazado" }.to_json)

      result = Up.new(API).run!

      assert_empty result[:transmitted]
      assert_equal 1, result[:failed].size
      assert_nil @order.reload.erp_folio
      assert @order.captured?, "sigue capturado para reintentar"
    end
  end
end
