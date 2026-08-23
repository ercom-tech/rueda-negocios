require "test_helper"

# La aplicación de promociones a un pedido: el acumulado que elige el
# escalón, el override por producto, los regalos y el congelamiento de las
# partidas. Las reglas y su porqué viven en Promotions::Group.
class PromotionsGroupTest < ActiveSupport::TestCase
  setup do
    @user   = User.create!(erp_person_id: 9301, username: "cap_pg", password: "x", role: "capturista")
    @round  = BusinessRound.create!(erp_round_id: 9301, name: "Rueda PG", active: true)
    @client = Client.create!(erp_client_key: "PG01", name: "Cliente PG")
    @brand  = Brand.create!(erp_brand_id: 9301, name: "Marca PG")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
  end

  def product(price: 100, max_discount: 5, erp_id: nil)
    p = Product.create!(erp_product_id: erp_id || rand(1_000_000..9_999_999),
                        description: "PRODUCTO #{rand(9999)}", brand: @brand,
                        unit: "PZA", max_discount: max_discount)
    Price.create!(product: p, credit_wholesale_price: price, tax_rate: 16)
    p
  end

  # Promoción con escalones como los reales de la rueda.
  def promotion(tiers:, products: [], unit: "MXN", starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    promo = Promotion.create!(erp_promotion_id: rand(1_000..9_999), code: "PRM",
                              name: "PROMO PRUEBA", starts_on: starts_on, ends_on: ends_on)
    tiers.each_with_index do |t, i|
      promo.promotion_tiers.create!(erp_consecutive: i + 1, unit: unit,
                                    condition_kind: t[:kind] || "CM",
                                    quantity_from: t[:from], quantity_to: t[:to] || 0,
                                    discount_percent: t[:percent])
    end
    products.each do |p|
      promo.promotion_products.create!(product: p, discount_percent: 0)
    end
    promo
  end

  def add_item(product, quantity: 1, discount: 0)
    @order.order_items.create!(product.to_order_item_attributes.merge(
      position: @order.next_item_position, quantity: quantity, discount_percent: discount
    ))
  end

  def group_for(promo)
    Promotions::Group.new(@order.reload, promo)
  end

  # --- Acumulado y escalón -----------------------------------------------

  test "el acumulado suma el importe bruto de las partidas del universo" do
    a, b, fuera = product(price: 1000), product(price: 500), product(price: 900)
    promo = promotion(tiers: [ { from: 1000, percent: 10 } ], products: [ a, b ])
    add_item(a, quantity: 2)   # 2,000
    add_item(b, quantity: 1)   #   500
    add_item(fuera, quantity: 5)

    group = group_for(promo)

    assert_equal 2500, group.accumulated, "la partida ajena al universo no debe sumar"
    assert_equal 10, group.tier.discount_percent
  end

  # Sin esta regla, un pedido de $25,000 de FANDELI se quedaba sin el regalo
  # que el proveedor prometió: sus escalones ≥15,000 y ≥20,000 se traslapan y
  # solo el segundo regala.
  test "entre escalones abiertos traslapados gana el de mínimo más alto" do
    a = product(price: 1000)
    promo = promotion(products: [ a ], tiers: [
      { kind: "CM", from: 15_000, percent: 9 },
      { kind: "CM", from: 20_000, percent: 9 }
    ])
    add_item(a, quantity: 25)  # 25,000

    assert_equal 20_000, group_for(promo).tier.quantity_from
  end

  test "un rango cerrado no aplica por encima de su tope" do
    a = product(price: 1000)
    promo = promotion(products: [ a ], tiers: [ { kind: "CE", from: 1000, to: 4999, percent: 5 } ])
    add_item(a, quantity: 6)   # 6,000 — fuera del rango

    assert_nil group_for(promo).tier
    assert_not group_for(promo).applicable?
  end

  test "una promoción medida en piezas cuenta cantidades, no pesos" do
    a = product(price: 1000)
    promo = promotion(products: [ a ], unit: "PZA", tiers: [ { from: 5, percent: 7 } ])
    add_item(a, quantity: 5)

    group = group_for(promo)
    assert_equal 5, group.accumulated
    assert_equal 7, group.tier.discount_percent
  end

  # "Por cada" multiplica, no escalona: aplicarlo como escalón regalaría un
  # descuento que nadie configuró así.
  test "un escalón por cada no se aplica a ciegas" do
    a = product(price: 1000)
    promo = promotion(products: [ a ], tiers: [ { kind: "PC", from: 20, percent: 15 } ])
    add_item(a, quantity: 50)

    assert_nil group_for(promo).tier
  end

  # --- Aplicar ------------------------------------------------------------

  test "aplicar pone el descuento del escalón en todas las partidas del grupo" do
    a, b = product(price: 1000, max_discount: 3), product(price: 500, max_discount: 3)
    promo = promotion(tiers: [ { from: 1000, percent: 12 } ], products: [ a, b ])
    add_item(a, quantity: 2)
    add_item(b, quantity: 1)

    assert group_for(promo).apply!

    percents = @order.reload.order_items.reject(&:gift?).map(&:discount_percent)
    assert_equal [ 12, 12 ], percents.map(&:to_i)
  end

  # El tope del producto es la brida del descuento MANUAL. Si topara también
  # a la promoción, casi ninguna de la rueda se podría aplicar: los topes van
  # de 3% a 9% y los descuentos llegan a 23%.
  test "la promoción rebasa el tope de descuento del producto" do
    a = product(price: 1000, max_discount: 5)
    promo = promotion(tiers: [ { from: 1000, percent: 23 } ], products: [ a ])
    add_item(a, quantity: 2)

    assert group_for(promo).apply!
    assert_equal 23, @order.reload.order_items.first.discount_percent.to_i
  end

  test "el override del producto gana sobre el escalón" do
    a, b = product(price: 1000), product(price: 1000)
    promo = promotion(tiers: [ { from: 1000, percent: 0 } ], products: [ b ])
    promo.promotion_products.create!(product: a, discount_percent: 20)
    add_item(a)
    add_item(b)

    group_for(promo).apply!

    by_product = @order.reload.order_items.to_h { |i| [ i.product_id, i.discount_percent.to_i ] }
    assert_equal 20, by_product[a.id], "FANAL lleva su escalón en 0% y el descuento en cada código"
    assert_equal 0,  by_product[b.id]
  end

  test "la promoción pisa el descuento tecleado y al quitarla lo devuelve" do
    a = product(price: 1000, max_discount: 5)
    promo = promotion(tiers: [ { from: 1000, percent: 12 } ], products: [ a ])
    add_item(a, quantity: 2, discount: 5)

    group_for(promo).apply!
    assert_equal 12, @order.reload.order_items.first.discount_percent.to_i

    group_for(promo).unapply!
    item = @order.reload.order_items.first
    assert_equal 5, item.discount_percent.to_i
    assert_nil item.promotion_id
    assert_nil item.manual_discount_percent, "la memoria del descuento manual no debe sobrevivir a su uso"
  end

  # Re-aplicar guardaba el descuento de la PROMOCIÓN como si fuera del
  # capturista: al quitarla se le quedaba pegado un 12% que él nunca tecleó.
  test "re-aplicar no reescribe la memoria del descuento manual" do
    a = product(price: 1000, max_discount: 5)
    promo = promotion(tiers: [ { from: 1000, percent: 12 } ], products: [ a ])
    add_item(a, quantity: 2, discount: 5)

    group_for(promo).apply!
    group_for(promo).apply!
    group_for(promo).unapply!

    assert_equal 5, @order.reload.order_items.first.discount_percent.to_i
  end

  test "una promoción fuera de vigencia no se puede aplicar" do
    a = product(price: 1000)
    promo = promotion(tiers: [ { from: 1000, percent: 10 } ], products: [ a ],
                      starts_on: 3.weeks.ago.to_date, ends_on: 2.weeks.ago.to_date)
    add_item(a, quantity: 2)

    group = group_for(promo)
    assert_not group.applicable?
    assert_match(/estuvo vigente/, group.blocked_reason)
    assert_not group.apply!
  end

  # --- Regalos ------------------------------------------------------------

  test "aplicar agrega el regalo del escalón y quitarla se lo lleva" do
    a, gift_product = product(price: 1000), product(price: 670.41)
    promo = promotion(tiers: [ { from: 1000, percent: 9 } ], products: [ a ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: gift_product, quantity: 1)
    add_item(a, quantity: 2)

    group_for(promo).apply!
    gifts = @order.reload.order_items.select(&:gift?)
    assert_equal 1, gifts.size
    assert_equal gift_product.id, gifts.first.product_id

    group_for(promo).unapply!
    assert_empty @order.reload.order_items.select(&:gift?)
  end

  # El regalo no le cuesta nada al cliente (decisión FECEGO 2026-08-22): 100%
  # de descuento sobre el precio de lista. El ERP deja los suyos en $0.29,
  # pero eso obligaba a cobrar centavos por algo prometido regalado —y el
  # papel del cliente lo mostraba.
  test "el regalo no cuesta nada" do
    a, gift_product = product(price: 1000), product(price: 68)
    promo = promotion(tiers: [ { from: 1000, percent: 9 } ], products: [ a ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: gift_product, quantity: 8)
    add_item(a, quantity: 2)

    group_for(promo).apply!

    gift = @order.reload.order_items.find(&:gift?)
    assert_equal 0, gift.total, "el regalo va en cero en pantalla, en el papel y en el ERP"
    assert_equal 100, gift.discount_percent.to_i
    # El precio de lista SÍ viaja: el ERP guarda precio y descuento por
    # separado, y una partida en precio 0 con descuento 100 no dice nada de
    # cuánto valía lo que se regaló.
    assert_equal 68, gift.unit_price.to_i
  end

  # El total del pedido no arrastra centavos del regalo: es lo que hace que
  # el PDF cuadre al sumar sus renglones y coincida con lo que factura el ERP.
  test "el regalo no mueve el total del pedido" do
    a, gift_product = product(price: 1000), product(price: 670.41)
    promo = promotion(tiers: [ { from: 1000, percent: 0 } ], products: [ a ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: gift_product, quantity: 1)
    add_item(a, quantity: 2)
    sin_regalo = @order.reload.total

    group_for(promo).apply!

    assert_equal sin_regalo, @order.reload.total
  end

  # El ERP guarda por separado lo que la promoción DICTÓ y lo que se aplicó.
  # En nuestros regalos coinciden en 100: dicta "entero" y así se cobra.
  test "el regalo dice al ERP que la promocion dicto 100 por ciento" do
    a, gift_product = product(price: 1000), product(price: 68)
    promo = promotion(tiers: [ { from: 1000, percent: 9 } ], products: [ a ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: gift_product, quantity: 8)
    add_item(a, quantity: 2)

    group_for(promo).apply!

    gift = @order.reload.order_items.find(&:gift?)
    assert_equal 100, gift.promotion_discount_percent.to_i
    assert_equal 100, gift.discount_percent.to_i
  end

  # El regalo cuelga del ESCALÓN: si colgara de la promoción, el pedido que
  # apenas alcanza el primer escalón se llevaría un premio que nadie prometió.
  test "solo llega el regalo del escalón alcanzado" do
    a = product(price: 1000)
    chico, grande = product(price: 50), product(price: 90)
    promo = promotion(products: [ a ], tiers: [
      { kind: "CE", from: 1000, to: 4999, percent: 5 },
      { kind: "CM", from: 5000, percent: 9 }
    ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: chico, quantity: 1)
    promo.promotion_tiers.last.promotion_gifts.create!(product: grande, quantity: 1)
    add_item(a, quantity: 2)   # 2,000 → primer escalón

    group_for(promo).apply!

    assert_equal [ chico.id ], @order.reload.order_items.select(&:gift?).map(&:product_id)
  end

  test "los regalos no cuentan contra el tope de partidas" do
    a, gift_product = product(price: 1000), product(price: 50)
    promo = promotion(tiers: [ { from: 1000, percent: 9 } ], products: [ a ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: gift_product, quantity: 1)
    add_item(a, quantity: 2)

    group_for(promo).apply!

    assert_equal 1, @order.reload.items_count_for_limit
    assert_equal 2, @order.order_items.size
  end

  # Un regalo sin precio entraría en $0.00: un faltante que el ERP no puede
  # explicar y que nadie configuró así.
  test "un regalo sin precio no se agrega" do
    a = product(price: 1000)
    sin_precio = Product.create!(erp_product_id: rand(1_000_000..9_999_999),
                                 description: "SIN PRECIO", brand: @brand, unit: "PZA")
    promo = promotion(tiers: [ { from: 1000, percent: 9 } ], products: [ a ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: sin_precio, quantity: 1)
    add_item(a, quantity: 2)

    group_for(promo).apply!

    assert_empty @order.reload.order_items.select(&:gift?)
  end

  # --- Congelamiento -------------------------------------------------------

  test "una partida con promoción aplicada no se puede editar" do
    a = product(price: 1000)
    promo = promotion(tiers: [ { from: 1000, percent: 12 } ], products: [ a ])
    add_item(a, quantity: 2)
    group_for(promo).apply!

    item = @order.reload.order_items.first
    assert_not item.update(quantity: 3)
    assert_match(/Quita la promoción para editarla/, item.errors.full_messages.to_sentence)
    assert_equal 2, item.reload.quantity.to_i
  end

  # El candado mira el valor ANTERIOR de promotion_id: soltar la promoción y
  # editar en la MISMA escritura lo abriría justo cuando debe cerrarse.
  # `promotion_id` no viaja en los params permitidos, así que esto solo llega
  # por un PATCH forjado — que es exactamente contra lo que el candado del
  # modelo existe, además del de la pantalla.
  test "soltar la promoción en la misma escritura no abre el candado" do
    # max_discount holgado A PROPÓSITO: con el tope por debajo del 12%, quien
    # rechazaba la escritura era `discount_within_limits` y la prueba pasaba
    # sin tocar el candado — verde por el camino equivocado.
    a = product(price: 1000, max_discount: 50)
    promo = promotion(tiers: [ { from: 1000, percent: 12 } ], products: [ a ])
    add_item(a, quantity: 2)
    group_for(promo).apply!

    item = @order.reload.order_items.first
    assert_not item.update(promotion_id: nil, quantity: 3)
    assert_equal 2, item.reload.quantity.to_i
  end

  test "una partida de regalo no se puede editar" do
    a, gift_product = product(price: 1000), product(price: 50)
    promo = promotion(tiers: [ { from: 1000, percent: 9 } ], products: [ a ])
    promo.promotion_tiers.first.promotion_gifts.create!(product: gift_product, quantity: 1)
    add_item(a, quantity: 2)
    group_for(promo).apply!

    gift = @order.reload.order_items.find(&:gift?)
    assert_not gift.update(quantity: 10)
    assert_match(/es un regalo de la promoción/, gift.errors.full_messages.to_sentence)
  end

  # Agregar cambiaría el acumulado, pero las partidas están congeladas: el
  # descuento se quedaría calculado sobre una suma vieja.
  test "no se puede agregar un producto de una promoción ya aplicada" do
    a, b = product(price: 1000), product(price: 500)
    promo = promotion(tiers: [ { from: 1000, percent: 12 } ], products: [ a, b ])
    add_item(a, quantity: 2)
    group_for(promo).apply!

    nueva = @order.order_items.build(b.to_order_item_attributes.merge(position: 9, quantity: 1))
    assert_not nueva.valid?
    assert_match(/Quita la promoción para agregarlo/, nueva.errors.full_messages.to_sentence)
  end

  test "un producto ajeno a la promoción aplicada sí se puede agregar" do
    a, fuera = product(price: 1000), product(price: 300)
    promo = promotion(tiers: [ { from: 1000, percent: 12 } ], products: [ a ])
    add_item(a, quantity: 2)
    group_for(promo).apply!

    assert add_item(fuera).persisted?
  end

  # --- El gancho del modal -------------------------------------------------

  test "el modal sabe cuánto falta para el siguiente escalón" do
    a = product(price: 1000)
    promo = promotion(products: [ a ], tiers: [
      { kind: "CE", from: 1000, to: 4999, percent: 5 },
      { kind: "CM", from: 5000, percent: 9 }
    ])
    add_item(a, quantity: 2)   # 2,000

    group = group_for(promo)
    assert_equal 5000, group.next_tier.quantity_from
    assert_equal 3000, group.missing_for_next_tier
  end

  test "en el escalón más alto ya no hay siguiente" do
    a = product(price: 1000)
    promo = promotion(products: [ a ], tiers: [ { from: 1000, percent: 9 } ])
    add_item(a, quantity: 2)

    assert_nil group_for(promo).next_tier
    assert_nil group_for(promo).missing_for_next_tier
  end
end
