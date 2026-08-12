require "test_helper"

# Cantidad inicial al agregar un producto al pedido.
#
# Hallazgo de la 3ª auditoría: `min_sale_quantity.presence || 1` devuelve 0.0
# cuando el empaque es CERO (sobre un decimal, `presence` no da nil), así que la
# partida nacía en cantidad 0, la validación la rechazaba y el producto quedaba
# invendible sin remedio offline.
class OrderItemsQuantityTest < ActionDispatch::IntegrationTest
  setup do
    @round  = BusinessRound.create!(erp_round_id: 1010, name: "Rueda 1010", active: true)
    @sup    = Supplier.create!(erp_supplier_id: 1010, name: "PROVEEDOR 1010")
    @brand  = Brand.create!(erp_brand_id: 1010, name: "MARCA 1010")
    @cap    = User.create!(erp_person_id: 1011, username: "cap1011", password: "secret123",
                           role: "capturista", active: true)
    BusinessRoundPerson.create!(business_round: @round, user: @cap, position: 1, supplier: @sup)
    @client = Client.create!(erp_client_key: "C1010", name: "Cliente 1010")
    @order  = Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission")
    post login_path, params: { username: "cap1011", password: "secret123" }
  end

  def product!(code, package)
    p = Product.create!(erp_product_id: code, description: "Producto #{code}", brand: @brand,
                        unit: "PZA", max_discount: 0, min_sale_quantity: package)
    ProductSupplier.create!(product: p, supplier: @sup)
    Price.create!(product: p, public_price: 100, tax_rate: 16)
    p
  end

  def add_product(product)
    post order_order_items_path(@order), params: { product_id: product.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  test "con empaque mínimo la cantidad arranca en el empaque" do
    assert_difference "OrderItem.count", 1 do
      add_product(product!(1_010_001, 10))
    end
    assert_equal 10, @order.order_items.last.quantity
  end

  test "sin empaque mínimo (nil) la cantidad arranca en 1" do
    assert_difference "OrderItem.count", 1 do
      add_product(product!(1_010_002, nil))
    end
    assert_equal 1, @order.order_items.last.quantity
  end

  test "con empaque mínimo CERO la cantidad arranca en 1, no en 0" do
    assert_difference "OrderItem.count", 1, "el producto debe poder agregarse" do
      add_product(product!(1_010_003, 0))
    end
    assert_equal 1, @order.order_items.last.quantity
    assert_no_match(/cantidad debe ser mayor/, response.body)
  end
  # El input debe usar el MISMO criterio que el controlador y el modelo: con
  # empaque 0 en el ERP, `min="0"` y paso 0 dejaban que la flecha ↓ bajara hasta
  # 0 y el modelo lo rechazara al salir del campo.
  test "un empaque cero no se convierte en min 0 ni en paso 0" do
    product = Product.create!(erp_product_id: 962_001, description: "Empaque cero",
                              brand: @brand, unit: "PZA", max_discount: 0, min_sale_quantity: 0)
    ProductSupplier.create!(product: product, supplier: @sup)
    Price.create!(product: product, public_price: 100, tax_rate: 16)
    item = @order.order_items.create!(product: product, position: 1, quantity: 1,
                                      unit_price: 100, tax_rate: 16, discount_percent: 0)

    get order_path(@order)

    assert_select "input##{ActionView::RecordIdentifier.dom_id(item, :quantity)}" do |input|
      assert_equal "1", input.first["min"], "sin empaque útil, el mínimo es 1"
      assert_nil input.first["data-step-size"], "no debe fijar un paso de 0"
    end
  end
end
