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

  test "cantidad no positiva es inválida con mensaje en español" do
    oi = item(quantity: 0, discount_percent: 0)
    assert_not oi.valid?
    assert_includes oi.errors.full_messages, "La cantidad debe ser mayor a 0."
  end

  test "una partida sin precio (unit_price 0) es inválida" do
    oi = item(unit_price: 0, discount_percent: 0)
    assert_not oi.valid?
    assert_includes oi.errors.full_messages,
                    "El producto no tiene precio de rueda; no se puede agregar al pedido."
  end
end
