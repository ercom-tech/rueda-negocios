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
    Price.create!(product: p, public_price: 100, credit_wholesale_price: 100, tax_rate: 16)
    p
  end

  def fill_order_to(count)
    count.times { |i| @order.order_items.create!(position: i + 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0) }
  end

  test "el POST de la partida excedente no crea el registro y avisa el motivo" do
    fill_order_to(Order::MAX_ITEMS)
    product = product!(950_001)

    assert_no_difference "OrderItem.count" do
      post order_order_items_path(@order), params: { product_id: product.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_match(/no puede tener más de #{Order::MAX_ITEMS} partidas/, response.body)
  end

  test "debajo del tope la partida sí se agrega" do
    fill_order_to(Order::MAX_ITEMS - 1)
    product = product!(950_002)

    assert_difference "OrderItem.count", 1 do
      post order_order_items_path(@order), params: { product_id: product.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  # El contador vive DENTRO del buscador (extremo derecho del pill), que es el
  # partial que ya se repinta con morph en cada alta/baja de partida.
  test "el contador de partidas se muestra dentro del buscador" do
    fill_order_to(3)

    get order_path(@order)
    assert_select "#product-search span", text: /Partidas\s*3\s*\/\s*#{Order::MAX_ITEMS}/
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

  # Al quitar una partida, el botón que abrió el modal se va con su fila y el
  # foco caía al <body>: había que retabular desde el inicio de la página en
  # cada baja. El stream del "focus director" lo manda al buscador.
  test "quitar una partida manda el foco al buscador" do
    fill_order_to(2)
    item = @order.order_items.first

    delete order_order_item_path(@order, item),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/focus-director/, response.body)
    assert_match(/data-focus-selector-value="#product-search input"/, response.body)
  end

  # Editar cantidad o descuento NO debe mover el foco: el director solo viaja
  # en la baja.
  test "editar una partida no manda el foco a ningún lado" do
    fill_order_to(2)
    item = @order.order_items.first

    patch order_order_item_path(@order, item), params: { order_item: { quantity: 3 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_no_match(/data-focus-selector-value/, response.body)
  end

  # --- Producto repetido ---------------------------------------------------
  # Agregar dos veces el mismo producto es legítimo (mismo producto con
  # distinto descuento), pero pasaba SIN NINGÚN AVISO: la sugerencia se veía
  # idéntica a la de uno nuevo y, con la tabla scrolleando, el duplicado no se
  # notaba. El pedido llegaba al ERP con dos renglones iguales y se surte doble.

  test "el buscador marca el producto que ya está en el pedido y en qué partida" do
    product = product!(950_010)
    @order.order_items.create!(position: 1, quantity: 1, unit_price: 100, tax_rate: 16,
                               discount_percent: 0, product: product)

    get product_options_order_path(@order), params: { q: "Producto 950010" }

    assert_match(/Ya está en el pedido, partida 1/, response.body)
    assert_match(/Agregar otra vez/, response.body)
  end

  test "un producto nuevo no se marca como repetido" do
    product!(950_011)

    get product_options_order_path(@order), params: { q: "Producto 950011" }

    assert_no_match(/Ya está en el pedido/, response.body)
    assert_match(/>\s*Agregar\s*</, response.body)
  end

  # La lista se cierra al elegir, así que el aviso previo ya no está a la vista:
  # se repite al agregarlo.
  test "agregar un producto repetido avisa con las dos partidas" do
    product = product!(950_012)
    @order.order_items.create!(position: 1, quantity: 1, unit_price: 100, tax_rate: 16,
                               discount_percent: 0, product: product)

    post order_order_items_path(@order), params: { product_id: product.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/ya estaba en la partida 1/, response.body)
    assert_match(/ahora está también en la 2/, response.body)
    assert_equal 2, @order.order_items.count, "no se bloquea: se avisa"
  end

  test "agregar un producto nuevo no avisa de nada" do
    product = product!(950_013)

    post order_order_items_path(@order), params: { product_id: product.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_no_match(/ya estaba en la partida/, response.body)
  end

  # Con el producto repetido, la descripción sola no dice cuál se va a quitar.
  test "el modal de quitar nombra la partida" do
    fill_order_to(2)

    get order_path(@order)

    assert_match(/¿Quitar la partida 1/, response.body)
    assert_match(/¿Quitar la partida 2/, response.body)
  end

  # Borrar una partida intermedia dejaba huecos en la columna Consecutivo.
  test "borrar una partida intermedia renumera el consecutivo" do
    fill_order_to(4)
    middle_item = @order.order_items.find_by(position: 2)

    delete order_order_item_path(@order, middle_item),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal [ 1, 2, 3 ], @order.order_items.reload.map(&:position)
  end
end
