require "test_helper"

# El producto fuera de catálogo (genérico 999999): cualquier capturista puede
# usarlo — incluso SIN membresía de proveedor ni marca, que es como corre este
# archivo — capturando descripción, no. de parte y precio a mano. Decisión
# FECEGO 2026-08-17.
class GenericItemTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 966_001, username: "cap_gen", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 966_001, name: "Rueda genérico", active: true)
    client = Client.create!(erp_client_key: "GEN01", name: "Cliente genérico")
    @order = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")
    @generic = Product.create!(erp_product_id: Product::GENERIC_ERP_ID,
                               description: "AJUSTE DE MERCANCIA", unit: "PZA", max_discount: 9)
    login_as "cap_gen"
  end

  def add_generic(description: "CESPOL DE HULE", part_number: "ABC-1", unit_price: "226.94")
    post order_order_items_path(@order),
         params: { product_id: @generic.id,
                   generic: { description: description, part_number: part_number, unit_price: unit_price } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  test "elegir el genérico responde el mini-formulario, no una partida" do
    assert_no_difference "OrderItem.count" do
      post order_order_items_path(@order), params: { product_id: @generic.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_match(/Producto fuera de catálogo/, response.body)
    assert_match(/generic\[description\]/, response.body)
    assert_match(/40 caracteres entre ambos/, response.body)
  end

  test "el segundo paso crea la partida con lo capturado, en mayúsculas" do
    assert_difference "OrderItem.count", 1 do
      add_generic(description: "cespol de hule", part_number: "abc-1")
    end

    item = @order.order_items.sole
    assert item.generic?
    assert_equal "CESPOL DE HULE", item.description
    assert_equal "ABC-1", item.part_number
    assert_equal 226.94, item.unit_price
    assert_equal 1, item.quantity
  end

  test "sin descripción no se crea y el formulario reaparece con aviso" do
    assert_no_difference "OrderItem.count" do
      add_generic(description: "")
    end

    assert_match(/Escribe la descripción del producto/, response.body)
    assert_match(/generic\[description\]/, response.body, "el formulario debe reaparecer")
  end

  test "varias partidas del genérico no avisan duplicado" do
    add_generic(description: "PRIMERA COSA")
    add_generic(description: "SEGUNDA COSA")

    assert_equal 2, @order.order_items.count
    assert_no_match(/ya estaba en la partida/, response.body)
  end

  test "la partida del genérico edita descripción, parte y precio" do
    add_generic
    item = @order.order_items.sole

    patch order_order_item_path(@order, item),
          params: { order_item: { description: "otra cosa", part_number: "", unit_price: "300" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    item.reload
    assert_equal "OTRA COSA", item.description
    assert_nil item.part_number
    assert_equal 300, item.unit_price
  end

  test "un producto de catálogo ignora esos campos en el PATCH (candado)" do
    supplier = Supplier.create!(erp_supplier_id: 966_001, name: "Prov gen")
    normal = Product.create!(erp_product_id: 966_010, description: "MARTILLO REAL", unit: "PZA")
    ProductSupplier.create!(product: normal, supplier: supplier)
    item = @order.order_items.create!(product: normal, position: 5, quantity: 1,
                                      unit_price: 100, tax_rate: 16, discount_percent: 0,
                                      code: "966010", description: "MARTILLO REAL", unit: "PZA")

    patch order_order_item_path(@order, item),
          params: { order_item: { description: "HACKEADO", unit_price: "1", quantity: "3" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    item.reload
    assert_equal "MARTILLO REAL", item.description, "la descripción es snapshot del ERP: no se toca"
    assert_equal 100, item.unit_price, "el precio es snapshot del ERP: no se toca"
    assert_equal 3, item.quantity, "la cantidad sí es editable"
  end
end
