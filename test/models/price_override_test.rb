require "test_helper"

class PriceOverrideTest < ActiveSupport::TestCase
  setup do
    @round   = BusinessRound.create!(erp_round_id: 9401, name: "Rueda PO", active: true)
    @product = Product.create!(erp_product_id: 3021, description: "MOTOSIERRA")
    Price.create!(product: @product, public_price: 7000, credit_wholesale_price: 6500, tax_rate: 16)
  end

  def override(**attrs)
    PriceOverride.create!({ erp_round_id: @round.erp_round_id, erp_product_id: 3021, unit_price: 6900 }.merge(attrs))
  end

  test "sin precio cargado se captura a crédito mayoreo" do
    assert_equal 6500, @product.capture_price
    assert_equal 6500, @product.to_order_item_attributes[:unit_price]
  end

  test "el precio cargado reemplaza al crédito mayoreo en la partida" do
    override

    assert_equal 6900, @product.reload.capture_price
    assert_equal 6900, @product.to_order_item_attributes[:unit_price]
    assert_equal 16, @product.to_order_item_attributes[:tax_rate], "el IVA sigue siendo el del ERP"
  end

  # Va por código, sin FK: el sync-down recrea el producto con otro id y el
  # precio tiene que seguir aplicando.
  test "aplica por código aunque el producto se haya recreado" do
    override
    @product.destroy!
    recreated = Product.create!(erp_product_id: 3021, description: "MOTOSIERRA")
    Price.create!(product: recreated, credit_wholesale_price: 6500, tax_rate: 16)

    assert_equal 6900, recreated.capture_price
  end

  test "solo aplica el de la rueda activa" do
    override(erp_round_id: 1)

    assert_equal 6500, @product.reload.capture_price, "el de otra rueda no cuenta"

    @round.update!(active: false)
    override
    assert_equal 6500, @product.reload.capture_price, "sin rueda activa no aplica ninguno"
  end

  test "se puede precargar sin una consulta por producto" do
    override
    other = Product.create!(erp_product_id: 3022, description: "OTRA")
    Price.create!(product: other, credit_wholesale_price: 10, tax_rate: 16)

    products = Product.where(id: [ @product.id, other.id ]).includes(:price, :price_override).to_a
    queries = 0
    counter = ->(*) { queries += 1 }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      assert_equal [ 6900, 10 ], products.sort_by(&:erp_product_id).map(&:capture_price)
    end
    assert_equal 0, queries
  end

  test "el precio tiene que ser mayor a cero" do
    [ 0, -1 ].each do |bad|
      record = PriceOverride.new(erp_round_id: @round.erp_round_id, erp_product_id: 3021, unit_price: bad)
      assert_not record.valid?, "#{bad} no debe aceptarse"
    end
  end

  # La base lo respalda aunque alguien se salte la validación.
  test "la base rechaza un precio en cero" do
    assert_raises(ActiveRecord::StatementInvalid) do
      PriceOverride.insert_all!([ { erp_round_id: @round.erp_round_id, erp_product_id: 3021, unit_price: 0 } ])
    end
  end

  test "un código por rueda" do
    override
    assert_not PriceOverride.new(erp_round_id: @round.erp_round_id, erp_product_id: 3021, unit_price: 1).valid?
  end

  test "el 999999 no admite precio cargado: se captura a mano" do
    record = PriceOverride.new(erp_round_id: @round.erp_round_id, erp_product_id: Product::GENERIC_ERP_ID, unit_price: 1)
    assert_not record.valid?
  end
end
