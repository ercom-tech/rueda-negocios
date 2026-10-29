require "test_helper"

# El Cotizador: el precio por pieza y por caja de una partida en cada escalón
# de su promoción. La regla vive en Promotions::Quote.
class PromotionsQuoteTest < ActiveSupport::TestCase
  setup do
    @user   = User.create!(erp_person_id: 9311, username: "cap_qt", password: "x", role: "capturista")
    @round  = BusinessRound.create!(erp_round_id: 9311, name: "Rueda QT", active: true)
    @client = Client.create!(erp_client_key: "QT01", name: "Cliente QT")
    @brand  = Brand.create!(erp_brand_id: 9311, name: "Marca QT")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
  end

  def product(price: 100, pieces_per_box: nil)
    p = Product.create!(erp_product_id: rand(1_000_000..9_999_999), description: "LIJA AGUA",
                        brand: @brand, unit: "PZA", max_discount: 0, pieces_per_box:)
    Price.create!(product: p, credit_wholesale_price: price, tax_rate: 16)
    p
  end

  def promotion(products:, tiers:, override: 0)
    promo = Promotion.create!(erp_promotion_id: rand(1_000..9_999), code: "PRM", name: "BTICINO - OAXACA 2026",
                              starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    tiers.each_with_index do |t, i|
      promo.promotion_tiers.create!(erp_consecutive: i + 1, unit: "MXN", condition_kind: t[:kind],
                                    quantity_from: t[:from], quantity_to: t[:to] || 0,
                                    discount_percent: t[:percent])
    end
    products.each { |p| promo.promotion_products.create!(product: p, discount_percent: override) }
    promo
  end

  def item_for(product)
    @order.order_items.create!(product.to_order_item_attributes.merge(position: @order.next_item_position,
                                                                      quantity: 1, discount_percent: 0))
  end

  TIERS = [ { kind: "CM", from: 125_000, percent: 12.12 },
            { kind: "CE", from: 10_000, to: 24_999, percent: 7.85 },
            { kind: "CE", from: 25_000, to: 74_999, percent: 9.27 } ].freeze

  # Cifras escritas a mano (no derivadas del código): pieza $100, caja de 10.
  test "un renglón por escalón, de menor a mayor, con pieza y caja" do
    sandpaper = product(price: 100, pieces_per_box: 10)
    promotion(products: [ sandpaper ], tiers: TIERS)

    rows = Promotions::Quote.new(item_for(sandpaper)).rows

    assert_equal [ "En la compra de entre $10,000 y $24,999", "En la compra de entre $25,000 y $74,999",
                   "En la compra mínima de $125,000" ], rows.map(&:condition)
    first = rows.first
    assert_equal [ 7.85, 100, 1000, 92.15, 921.5 ],
                 [ first.percent, first.piece_price, first.box_price, first.promo_piece_price, first.promo_box_price ]
  end

  # Caja de 500 de $0.40 al 7.85%: con la pieza ya redondeada ($0.37 × 500)
  # saldría en $185.00; redondeando una sola vez, como una partida, $184.30.
  test "la caja con promoción se redondea al final, no pieza por pieza" do
    sandpaper = product(price: BigDecimal("0.4"), pieces_per_box: 500)
    promotion(products: [ sandpaper ], tiers: [ { kind: "CM", from: 1, percent: 7.85 } ])

    row = Promotions::Quote.new(item_for(sandpaper)).rows.sole

    assert_equal BigDecimal("0.37"), row.promo_piece_price
    assert_equal BigDecimal("184.3"), row.promo_box_price
  end

  test "sin piezas por caja, o con caja de 1, no hay columnas de caja" do
    [ nil, 1 ].each do |pieces|
      sandpaper = product(pieces_per_box: pieces)
      promotion(products: [ sandpaper ], tiers: TIERS)
      quote = Promotions::Quote.new(item_for(sandpaper))

      assert_not quote.boxes?, pieces.inspect
      assert quote.rows.all? { |row| row.box_price.nil? && row.promo_box_price.nil? }, pieces.inspect
    end
  end

  # FANAL: el escalón en 0% y el descuento real en el código.
  test "el descuento propio del producto gana sobre el del escalón" do
    sandpaper = product(price: 100)
    promotion(products: [ sandpaper ], tiers: [ { kind: "CM", from: 1, percent: 0 } ], override: 20)

    row = Promotions::Quote.new(item_for(sandpaper)).rows.sole

    assert_equal [ 20, 80 ], [ row.percent, row.promo_piece_price ]
  end

  test "un escalón 'por cada' no se cotiza" do
    sandpaper = product
    promotion(products: [ sandpaper ], tiers: [ { kind: "PC", from: 10, percent: 5 }, { kind: "CM", from: 1, percent: 3 } ])

    assert_equal [ 3 ], Promotions::Quote.new(item_for(sandpaper)).rows.map(&:percent)
  end

  test "un producto sin promoción no tiene renglones" do
    quote = Promotions::Quote.new(item_for(product))

    assert_nil quote.promotion
    assert_empty quote.rows
  end

  # El precio de la partida, no el del catálogo: un archivo de precios
  # cargado DESPUÉS de agregarla no cambia lo que ese pedido cobra.
  test "cotiza con el precio de la partida" do
    sandpaper = product(price: 100)
    promotion(products: [ sandpaper ], tiers: [ { kind: "CM", from: 1, percent: 10 } ])
    item = item_for(sandpaper)
    sandpaper.price.update!(credit_wholesale_price: 300)

    assert_equal 90, Promotions::Quote.new(item.reload).rows.sole.promo_piece_price
  end

  # El ERP escribe la pieza como "PZA." (con punto); "2PZA" es un paquete de
  # dos y NO es pieza.
  test "solo la unidad PZA cuenta como pieza" do
    { "PZA." => true, "PZA" => true, " pza. " => true, "2PZA" => false, "CAJA" => false, "PQ10" => false }
      .each do |unit, expected|
        sandpaper = product
        sandpaper.update!(unit:)
        assert_equal expected, Promotions::Quote.new(item_for(sandpaper)).by_piece?, unit.inspect
      end
  end

  # La vigencia se mide en la fecha de CAPTURA del pedido, como la flama y la
  # aplicación (`Group`), no hoy: un borrador abierto el último día de la
  # promoción mostraba la flama y el Cotizador decía "no está en ninguna"
  # (14ª auditoría: cambiar a `Date.current` dejaba la suite en verde).
  test "la vigencia se mide en la fecha de captura del pedido, no hoy" do
    sandpaper = product(price: 100)
    promo = promotion(products: [ sandpaper ], tiers: [ { kind: "CM", from: 1, percent: 10 } ])
    promo.update!(starts_on: 10.days.ago.to_date, ends_on: 3.days.ago.to_date)
    @order.update_columns(created_at: 5.days.ago)

    assert_equal promo, Promotions::Quote.new(item_for(sandpaper)).promotion
  end
end
