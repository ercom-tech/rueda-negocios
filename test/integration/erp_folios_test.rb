require "test_helper"

# El pedido de la rueda entra al ERP partido en varios (las partidas de
# catálogo se cortan cada 45 y los productos nuevos van aparte). El detalle del
# pedido tiene que decir en CUÁLES quedó: es el único lugar donde el operador
# puede saberlo, y sin eso la lista de folios parecería un error en vez de una
# separación.
class ErpFoliosTest < ActionDispatch::IntegrationTest
  setup do
    @user   = User.create!(erp_person_id: 981, username: "cap981", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 981, name: "Rueda 981", active: true)
    Setting.instance.update!(selected_round_erp_id: 981, selected_round_name: "Rueda 981")
    @sup    = Supplier.create!(erp_supplier_id: 981, name: "PROVEEDOR")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @sup, position: 1)
    @client = Client.create!(erp_client_key: "C981", name: "Cliente")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")

    product = Product.create!(erp_product_id: 981_001, description: "UNO", max_discount: 50)
    Price.create!(product: product, credit_wholesale_price: 100, tax_rate: 16)
    ProductSupplier.create!(product: product, supplier: @sup)
    @order.order_items.create!(product: product, position: 1, quantity: 1, unit_price: 100,
                               discount_percent: 0, tax_rate: 16, code: product.erp_code,
                               description: "UNO", unit: "PZA")
    login_as "cap981"
  end

  def transmit!(folios)
    @order.update!(status: :captured, local_folio: "RN-000981",
                   erp_folio: folios.first, erp_folios: folios, transmitted_at: Time.current)
    @order.update!(status: :transmitted)
  end

  test "un pedido que se partió dice en cuáles quedó y cuántos son" do
    transmit!(%w[1A0007 1A0008 1A0009])

    get order_path(@order)

    assert_response :success
    assert_match(/1A0007, 1A0008, 1A0009/, response.body)
    assert_match(/se separó en 3 pedidos/, response.body)
  end

  # Con un folio no hay nada que explicar: decir "se separó en 1 pedidos" sería
  # ruido, y además con la concordancia rota.
  test "un pedido que no se partió muestra su folio a secas" do
    transmit!(%w[1A0007])

    get order_path(@order)

    assert_match(/En el ERP: 1A0007/, response.body)
    assert_no_match(/se separó/, response.body)
  end

  test "un pedido sin transmitir no anuncia folios del ERP" do
    get order_path(@order)

    assert_response :success
    assert_no_match(/En el ERP/, response.body)
  end
end
