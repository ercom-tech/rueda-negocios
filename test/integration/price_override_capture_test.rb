require "test_helper"

# El precio cargado desde archivo (PriceOverride) de punta a punta en la
# captura: el buscador lo anuncia y la partida nace con él. Si cada uno leyera
# su propio precio, el capturista ofrecería uno y el pedido cobraría otro.
class PriceOverrideCaptureTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 973_001, username: "cap_po", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 973_001, name: "Rueda 973", active: true)
    Setting.instance.update!(selected_round_erp_id: 973_001, selected_round_name: "Rueda 973")
    sup = Supplier.create!(erp_supplier_id: 973_001, name: "PROVEEDOR")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: sup, position: 1)
    @product = Product.create!(erp_product_id: 973_101, description: "MOTOSIERRA PO", max_discount: 50, unit: "PZA")
    Price.create!(product: @product, credit_wholesale_price: 429.44, tax_rate: 16)
    ProductSupplier.create!(product: @product, supplier: sup)
    PriceOverride.create!(erp_round_id: 973_001, erp_product_id: 973_101, unit_price: 512.30)
    client = Client.create!(erp_client_key: "PO01", name: "Cliente")
    @order = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")
    login_as "cap_po"
  end

  test "el buscador anuncia el precio cargado, no el del ERP" do
    get product_options_order_path(@order, q: "MOTOSIERRA")

    assert_match(/\$512\.30/, response.body)
    assert_no_match(/\$429\.44/, response.body)
  end

  test "la partida nace con el precio cargado" do
    post order_order_items_path(@order), params: { product_id: @product.id }, as: :turbo_stream

    assert_equal 512.30, @order.order_items.sole.unit_price
  end
end
