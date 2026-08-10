require "test_helper"

# Tope de partidas por pedido (Order::MAX_ITEMS): regla de negocio de la rueda
# — el ERP no la impone. Se valida en el modelo (cubre POST forjado) y se
# refleja en la UI: contador siempre visible y buscador deshabilitado al tope.
class OrderItemsLimitTest < ActionDispatch::IntegrationTest
  setup do
    @user   = User.create!(erp_person_id: 950, username: "cap950", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 950, name: "Rueda 950", active: true)
    @sup    = Supplier.create!(erp_supplier_id: 950, name: "PROVEEDOR 950")
    @brand  = Brand.create!(erp_brand_id: 950, name: "MARCA 950")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: @sup)
    @client = Client.create!(erp_client_key: "C950", name: "Cliente 950")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    post login_path, params: { username: "cap950", password: "secret123" }
  end

  # Producto dentro del universo del capturista (proveedor de su membresía),
  # con precio de rueda: si no, la partida se rechaza por otro motivo.
  def product!(code)
    p = Product.create!(erp_product_id: code, description: "Producto #{code}",
                        brand: @brand, unit: "PZA", max_discount: 0)
    ProductSupplier.create!(product: p, supplier: @sup)
    Price.create!(product: p, public_price: 100, tax_rate: 16)
    p
  end

  def fill_order_to(count)
    count.times { |i| @order.order_items.create!(position: i + 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0) }
  end

  test "el POST de la partida excedente no crea el registro y avisa el motivo" do
    fill_order_to(Order::MAX_ITEMS)
    producto = product!(950_001)

    assert_no_difference "OrderItem.count" do
      post order_order_items_path(@order), params: { product_id: producto.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_match(/no puede tener más de #{Order::MAX_ITEMS} partidas/, response.body)
  end

  test "debajo del tope la partida sí se agrega" do
    fill_order_to(Order::MAX_ITEMS - 1)
    producto = product!(950_002)

    assert_difference "OrderItem.count", 1 do
      post order_order_items_path(@order), params: { product_id: producto.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "el contador de partidas se muestra en la tabla" do
    fill_order_to(3)

    get order_path(@order)
    assert_match(/Partidas\s*3\s*\/\s*#{Order::MAX_ITEMS}/, response.body)
  end

  test "al tope el buscador queda deshabilitado con el aviso" do
    fill_order_to(Order::MAX_ITEMS)

    get order_path(@order)
    assert_match(/Alcanzaste el máximo de #{Order::MAX_ITEMS} partidas/, response.body)
    assert_match(/disabled/, response.body)
  end

  test "debajo del tope el buscador está activo" do
    get order_path(@order)
    assert_match(/Busca por código, nombre, modelo/, response.body)
    assert_no_match(/Alcanzaste el máximo/, response.body)
  end
end
