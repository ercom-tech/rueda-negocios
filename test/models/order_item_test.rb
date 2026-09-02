require "test_helper"

class OrderItemTest < ActiveSupport::TestCase
  setup do
    user   = User.create!(erp_person_id: 9101, username: "cap_oi", password: "x", role: "capturista")
    round  = BusinessRound.create!(erp_round_id: 9101, name: "Rueda OI", active: true)
    client = Client.create!(erp_client_key: "OI01", name: "Cliente OI")
    @order = Order.create!(user: user, business_round: round, client: client, kind: "remission")
    @brand = Brand.create!(erp_brand_id: 9101, name: "Marca OI")
  end

  def product(max_discount)
    Product.create!(erp_product_id: rand(1_000_000..9_999_999), description: "P",
                    brand: @brand, unit: "PZA", max_discount: max_discount)
  end

  def item(attrs)
    @order.order_items.build({ quantity: 1, unit_price: 100, tax_rate: 16 }.merge(attrs))
  end

  test "descuento sobre el máximo del producto es inválido" do
    oi = item(product: product(5), discount_percent: 9)
    assert_not oi.valid?
    assert_includes oi.errors.full_messages, "El descuento no puede exceder el máximo del producto (5%)."
  end

  test "descuento igual al máximo del producto es válido" do
    assert item(product: product(5), discount_percent: 5).valid?
  end

  # --- Producto fuera de catálogo (genérico 999999) ----------------------

  def generic_product
    @generic_product ||= Product.create!(erp_product_id: Product::GENERIC_ERP_ID,
                                         description: "AJUSTE DE MERCANCIA",
                                         unit: "PZA", max_discount: 9)
  end

  def generic_item(attrs = {})
    item({ product: generic_product, description: "CESPOL DE HULE P/LAVABO",
           unit_price: 226.94 }.merge(attrs))
  end

  test "el genérico exige descripción" do
    oi = generic_item(description: "")
    assert_not oi.valid?
    assert_includes oi.errors.full_messages, "Escribe la descripción del producto."
  end

  test "descripción y parte del genérico deben caber juntos en los 40 del ERP" do
    # 30 + espacio + 15 = 46 → sobran 6 del varchar(40) de nombre_capturado.
    oi = generic_item(description: "A" * 30, part_number: "B" * 15)
    assert_not oi.valid?
    assert oi.errors.full_messages.any? { |m| m.include?("sobran 6 caracteres") }, oi.errors.full_messages.inspect
  end

  test "el genérico admite descuento libre por encima del tope del producto" do
    # max_discount 9 (el del ERP): en el genérico no aplica — decisión FECEGO
    # 2026-08-17. Solo lo acotan 0 y 100.
    assert generic_item(discount_percent: 50).valid?
    assert_not generic_item(discount_percent: 101).valid?
  end

  test "el genérico exige precio capturado y con tope de columna" do
    oi = generic_item(unit_price: nil)
    assert_not oi.valid?
    assert_includes oi.errors.full_messages, "Escribe el precio unitario (mayor a cero)."

    assert_not generic_item(unit_price: OrderItem::MAX_UNIT_PRICE).valid?
  end

  test "el genérico normaliza a mayúsculas y arma el nombre que viaja al ERP" do
    oi = generic_item(description: "  cespol de hule ", part_number: " abc-1 ")
    assert oi.valid?, oi.errors.full_messages.inspect
    assert_equal "CESPOL DE HULE", oi.description
    assert_equal "CESPOL DE HULE ABC-1", oi.erp_captured_name
  end

  test "un producto de catálogo no es genérico y conserva sus reglas" do
    oi = item(product: product(5), discount_percent: 3)
    assert_not oi.generic?
    assert oi.valid?
  end

  test "borrar el descuento (campo vacío) significa 0 y se guarda sin tronar" do
    oi = item(product: product(5), discount_percent: 5)
    oi.save!

    # Lo que manda el form al vaciar el campo y dar tab: "" → antes reventaba
    # con PG::NotNullViolation; debe normalizarse a 0.
    assert oi.update(discount_percent: "")
    assert_equal 0, oi.reload.discount_percent
    assert_equal 0, oi.discount_amount
  end

  test "max_discount 0 bloquea cualquier descuento" do
    assert_not item(product: product(0), discount_percent: 1).valid?
    assert item(product: product(0), discount_percent: 0).valid?
  end

  test "max_discount nil se trata como 0: no aplica descuentos" do
    oi = item(product: product(nil), discount_percent: 1)
    assert_not oi.valid?
    assert item(product: product(nil), discount_percent: 0).valid?
  end

  test "sin producto tampoco se permite descuento" do
    assert_not item(product: nil, discount_percent: 1).valid?
  end

  test "producto con empaque mínimo: solo se vende en múltiplos" do
    p = product(0)
    p.update!(min_sale_quantity: 6)

    assert item(product: p, quantity: 6).valid?
    assert item(product: p, quantity: 18).valid?

    oi = item(product: p, quantity: 7)
    assert_not oi.valid?
    assert_includes oi.errors.full_messages,
                    "El producto se vende en múltiplos de 6 (empaque mínimo de venta)."
  end

  test "sin empaque mínimo (nil) no hay regla de múltiplos" do
    assert item(product: product(0), quantity: 7).valid?
  end

  # Un empaque 0 en el ERP no es regla de múltiplos: si se tratara como tal, la
  # partida nacería en cantidad 0 y el producto quedaría invendible.
  test "empaque mínimo 0 se trata como sin regla" do
    p = product(0)
    p.update!(min_sale_quantity: 0)

    assert item(product: p, quantity: 1).valid?
    assert item(product: p, quantity: 7).valid?
  end

  test "empaque mínimo decimal también valida múltiplos exactos" do
    p = product(0)
    p.update!(min_sale_quantity: 2.5)

    assert item(product: p, quantity: 7.5).valid?
    assert_not item(product: p, quantity: 6).valid?
  end

  test "cantidad no positiva es inválida con mensaje en español" do
    oi = item(quantity: 0, discount_percent: 0)
    assert_not oi.valid?
    assert_includes oi.errors.full_messages, "La cantidad debe ser mayor a 0."
  end

  test "una partida sin precio (unit_price 0) es inválida" do
    oi = item(unit_price: 0, discount_percent: 0)
    assert_not oi.valid?
    assert_includes oi.errors.full_messages,
                    "El producto no tiene precio de rueda; no se puede agregar del catálogo. " \
                    "Captúralo fuera de catálogo (999999) con su precio, o avisa al equipo del servidor."
  end

  # --- Sin tope de partidas (2026-09-02) ----------------------------------
  # El de 45 era regla de negocio nuestra, no del ERP, y en la operación real
  # del evento estorbaba: un cliente grande no cabía en un pedido. Se quitó.

  def fill_order_to(count)
    count.times { |i| @order.order_items.create!(position: i + 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0) }
  end

  test "un pedido admite muchas más de 45 partidas" do
    fill_order_to(60)

    partida = item(discount_percent: 0, position: 61)

    assert partida.save, "la partida 61 debe caber: ya no hay tope"
    assert_equal 61, @order.reload.items_count
  end

  test "ninguna partida se rechaza por cantidad de renglones" do
    fill_order_to(120)

    partida = item(discount_percent: 0, position: 121)

    assert partida.valid?
    assert_empty partida.errors.full_messages.grep(/no puede tener más de/)
  end

  # El contador del buscador cuenta TODAS las partidas, regalos incluidos
  # (decisión del usuario): tiene que cuadrar con lo que se ve en la tabla.
  test "el contador incluye los regalos" do
    fill_order_to(3)
    regalo = @order.order_items.new(position: 4, quantity: 1, unit_price: 100,
                                    tax_rate: 16, discount_percent: 100)
    regalo.gift = true
    regalo.save!(validate: false)

    assert_equal 4, @order.reload.items_count
  end
end
