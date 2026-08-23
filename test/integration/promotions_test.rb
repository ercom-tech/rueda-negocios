require "test_helper"

# Aplicar y quitar una promoción desde la pantalla de captura: la flama, el
# modal, y los candados que quedan puestos mientras está aplicada.
class PromotionsTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 9401, username: "cap_pr", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 9401, name: "Rueda PR", active: true)
    Setting.instance.update!(selected_round_erp_id: 9401, selected_round_name: "Rueda PR")
    @client   = Client.create!(erp_client_key: "PR01", name: "Cliente PR")
    @supplier = Supplier.create!(erp_supplier_id: 9401, name: "MAKITA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @supplier, position: 1)

    @product = make_product("ROTOMARTILLO", 1000)
    @order   = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    @promo   = Promotion.create!(erp_promotion_id: 3039, code: "MAKR20", name: "MAKITA - OAXACA 2026",
                                 starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    @promo.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CE", unit: "MXN",
                                   quantity_from: 1000, quantity_to: 4999, discount_percent: 7)
    @promo.promotion_tiers.create!(erp_consecutive: 2, condition_kind: "CM", unit: "MXN",
                                   quantity_from: 5000, quantity_to: 0, discount_percent: 14)
    @promo.promotion_products.create!(product: @product, discount_percent: 0)

    login_as "cap_pr"
  end

  def make_product(description, price, erp_id: nil)
    product = Product.create!(erp_product_id: erp_id || rand(1_000_000..9_999_999),
                              description: description, unit: "PZA", max_discount: 9)
    Price.create!(product: product, credit_wholesale_price: price, tax_rate: 16)
    ProductSupplier.create!(product: product, supplier: @supplier)
    product
  end

  def add_item(product, quantity)
    @order.order_items.create!(product.to_order_item_attributes.merge(
      position: @order.next_item_position, quantity: quantity, discount_percent: 0
    ))
  end

  # --- La flama en la fila --------------------------------------------------

  test "un producto en promoción enciende la flama en su fila" do
    add_item(@product, 2)

    get order_path(@order)

    assert_response :success
    assert_match(/Promoción MAKITA - OAXACA 2026/, response.body)
  end

  # El contenido del modal NO viene en la página: viaja en un turbo-frame que
  # se pide al abrirlo. El cascarón es `data-turbo-permanent` (para sobrevivir
  # al morph) y Turbo conserva su subárbol entero, así que renderizarlo de
  # fábrica lo dejaría congelado — tras aplicar seguiría ofreciendo "Aplicar".
  test "la página trae el cascarón del modal, no su contenido" do
    add_item(@product, 2)

    get order_path(@order)

    assert_match(/id="promotion-frame-#{@promo.id}"/, response.body)
    assert_match(%r{/orders/#{@order.id}/promotions/#{@promo.id}}, response.body)
    assert_no_match(/En la compra de entre/, response.body)
  end

  test "el detalle del modal muestra la escalera y el gancho del siguiente escalón" do
    add_item(@product, 2)   # 2,000 → primer escalón (7%)

    get order_promotion_path(@order, @promo)

    assert_match(/En la compra de entre/, response.body)
    assert_match(/En la compra mínima de/, response.body)
    # El gancho: faltan 3,000 para el 14%. La cifra va en su propio <span>,
    # así que el texto llega partido por el marcado.
    assert_match(/Con\s+<span[^>]*>\$3,000\.00<\/span>\s+más/, response.body)
    assert_match(/subes a/, response.body)
    assert_match(/Aplicar promoción/, response.body)
  end

  # El detalle se pide en cada apertura, así que refleja el estado de AHORA.
  test "con la promoción aplicada, el detalle ofrece quitarla" do
    add_item(@product, 6)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    get order_promotion_path(@order, @promo)

    assert_match(/Quitar promoción/, response.body)
    assert_no_match(/Aplicar promoción/, response.body)
    assert_match(/no se pueden agregar más productos de esta promoción/, response.body)
  end

  # Leer el detalle no escribe nada: un pedido transmitido puede consultarlo,
  # y una pausa por sync no lo bloquea.
  test "el detalle de un pedido transmitido se puede ver sin botones" do
    add_item(@product, 6)
    @order.update!(status: "transmitted", erp_folio: "1A0007", transmitted_at: Time.current)

    get order_promotion_path(@order, @promo)

    assert_response :success
    assert_match(/En la compra mínima de/, response.body)
    assert_no_match(/Aplicar promoción/, response.body)
    assert_no_match(/Quitar promoción/, response.body)
  end

  # El modal es uno por PROMOCIÓN, no por fila: con 45 renglones del mismo
  # proveedor serían 45 copias idénticas repintándose en cada tecla.
  test "varias partidas de la misma promoción comparten un solo modal" do
    otro = make_product("ESMERIL", 500)
    @promo.promotion_products.create!(product: otro, discount_percent: 0)
    add_item(@product, 2)
    add_item(otro, 2)

    get order_path(@order)

    assert_equal 1, response.body.scan(/id="promotion-dialog-#{@promo.id}"/).size
  end

  # El ícono de regalo decía que había premio, no cuál. Quien todavía no
  # alcanza el escalón es justo el que necesita saberlo para decidir si sube.
  test "el detalle nombra los regalos de un escalón que aún no se alcanza" do
    gift_product = make_product("SOLDADURA DEVCON SC-10", 68)
    @promo.promotion_tiers.last.promotion_gifts.create!(product: gift_product, quantity: 8)
    add_item(@product, 2)   # 2,000 → primer escalón; el del regalo es el de 5,000

    get order_promotion_path(@order, @promo)

    assert_match(/8 × SOLDADURA DEVCON SC-10/, response.body)
    # Y el gancho lo nombra, no solo lo insinúa.
    assert_match(/y te llevas/, response.body)
    assert_no_match(/te llevas un regalo/, response.body)
  end

  # Con varios regalos el gancho da la cuenta y la escalera los detalla: dos
  # nombres largos del ERP dentro de la frase la vuelven ilegible.
  test "con varios regalos el gancho cuenta y la escalera nombra" do
    uno = make_product("EXHIBIDOR HERRAJES ZERO FUG 6010", 1.28)
    dos = make_product("EXHIBIDOR DE LINEA 6011", 0.35)
    @promo.promotion_tiers.last.promotion_gifts.create!(product: uno, quantity: 1)
    @promo.promotion_tiers.last.promotion_gifts.create!(product: dos, quantity: 1)
    add_item(@product, 2)

    get order_promotion_path(@order, @promo)

    assert_match(/te llevas <span[^>]*>2 regalos/, response.body)
    assert_match(/1 × EXHIBIDOR HERRAJES ZERO FUG 6010/, response.body)
    assert_match(/1 × EXHIBIDOR DE LINEA 6011/, response.body)
  end

  # --- Aplicar --------------------------------------------------------------

  test "aplicar deja el descuento del escalón y bloquea las partidas" do
    add_item(@product, 6)   # 6,000 → segundo escalón (14%)

    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    assert_response :success
    item = @order.order_items.first.reload
    assert_equal 14, item.discount_percent.to_i
    assert_equal @promo.id, item.promotion_id
    assert_match(/Se aplicó la promoción/, response.body)
    assert_match(/Quita la promoción para editarla/,
                 @order.order_items.first.tap { |i| i.update(quantity: 7) }.errors.full_messages.to_sentence)
  end

  # El tope del producto (9%) es la brida del descuento MANUAL: si topara a la
  # promoción, la de MAKITA al 14% no se podría aplicar nunca.
  test "la promoción pasa por encima del tope de descuento del producto" do
    add_item(@product, 6)

    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    assert_equal 14, @order.order_items.first.reload.discount_percent.to_i
  end

  test "sin alcanzar el mínimo, aplicar responde con el motivo y no toca nada" do
    barato = make_product("BROCA", 10)
    @promo.promotion_products.create!(product: barato, discount_percent: 0)
    add_item(barato, 1)   # 10 — muy por debajo del primer escalón

    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    # El texto dice cuánto falta para el escalón que SIGUE, no un mínimo que
    # el pedido quizá ya rebasó (7ª auditoría: con $14,999 recitaba $10,000).
    assert_match(/Te faltan \$990\.00 para el descuento del 7%/, response.body)
    assert_nil @order.order_items.first.reload.promotion_id
  end

  # --- Quitar ---------------------------------------------------------------

  test "quitar devuelve el descuento que el capturista tenía tecleado" do
    add_item(@product, 6)
    @order.order_items.first.update!(discount_percent: 5)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }
    assert_equal 14, @order.order_items.first.reload.discount_percent.to_i

    delete order_promotion_path(@order, @promo)

    item = @order.order_items.first.reload
    assert_equal 5, item.discount_percent.to_i
    assert_nil item.promotion_id
    assert_match(/La partida vuelve a ser editable/, response.body)
  end

  # --- Los candados ---------------------------------------------------------

  test "con la promoción aplicada no se puede agregar otro producto suyo" do
    otro = make_product("ESMERIL", 500)
    @promo.promotion_products.create!(product: otro, discount_percent: 0)
    add_item(@product, 6)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    assert_no_difference -> { @order.order_items.count } do
      post order_order_items_path(@order), params: { product_id: otro.id }
    end
    assert_match(/Quita la promoción para agregarlo/, response.body)
  end

  test "un producto ajeno a la promoción sí se puede agregar" do
    ajeno = make_product("MARTILLO", 300)
    add_item(@product, 6)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    assert_difference -> { @order.order_items.count }, 1 do
      post order_order_items_path(@order), params: { product_id: ajeno.id }
    end
  end

  test "la partida bloqueada no se puede editar desde la pantalla" do
    add_item(@product, 6)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }
    item = @order.order_items.first

    patch order_order_item_path(@order, item), params: { order_item: { quantity: 9 } }

    assert_equal 6, item.reload.quantity.to_i
    assert_match(/Quita la promoción para editarla/, response.body)
  end

  # --- Lo que la 7ª auditoría encontró --------------------------------------

  # El candado de edición era `on: :update` y no cubría el borrado: la pantalla
  # esconde el bote, pero el endpoint seguía vivo. Y borrar PARTE del grupo
  # dejaba al resto con un descuento que ya no se gana, rumbo al ERP.
  test "una partida congelada no se puede borrar" do
    add_item(@product, 6)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }
    item = @order.order_items.first

    assert_no_difference -> { @order.order_items.count } do
      delete order_order_item_path(@order, item)
    end
    assert_match(/Quita la promoción para quitarla del pedido/, response.body)
  end

  test "una partida de regalo tampoco se puede borrar" do
    gift_product = make_product("SOLDADURA", 68)
    @promo.promotion_tiers.last.promotion_gifts.create!(product: gift_product, quantity: 8)
    add_item(@product, 6)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }
    gift = @order.order_items.reload.find(&:gift?)

    assert_no_difference -> { @order.order_items.count } do
      delete order_order_item_path(@order, gift)
    end
    assert_match(/es un regalo de la promoción/, response.body)
  end

  # La primera pasada restaura el manual y vacía la memoria; la segunda ya no
  # encontraba nada y aterrizaba en 0, con el flash afirmando que quitó algo.
  test "quitar una promoción que ya no estaba no borra el descuento tecleado" do
    add_item(@product, 6)
    @order.order_items.first.update!(discount_percent: 5)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }
    delete order_promotion_path(@order, @promo)
    assert_equal 5, @order.order_items.first.reload.discount_percent.to_i

    delete order_promotion_path(@order, @promo)

    assert_equal 5, @order.order_items.first.reload.discount_percent.to_i
    assert_match(/ya no estaba aplicada/, response.body)
  end

  # Con override por producto, el modal leía el 0% del escalón y el flash
  # tomaba el de la primera partida como si valiera para todas.
  test "el modal y el flash anuncian el descuento que de verdad se aplica" do
    otro = make_product("CANDADO", 500)
    @promo.promotion_products.create!(product: otro, discount_percent: 20)
    @promo.promotion_products.find_by(product: @product).update!(discount_percent: 10)
    add_item(@product, 6)
    add_item(otro, 1)

    get order_promotion_path(@order, @promo)
    assert_match(/10% y 20% de descuento/, response.body)
    assert_match(/según el producto/, response.body)

    post order_promotions_path(@order), params: { promotion_id: @promo.id }
    assert_match(/10% y 20% según el producto en 2 partidas/, response.body)
    assert_equal [ 10, 20 ], @order.order_items.reload.map { |i| i.discount_percent.to_i }.sort
  end

  # El flash de aplicar tiene que decir que las partidas quedaron bloqueadas:
  # el único texto que lo explicaba vivía detrás de un clic en la flama.
  test "el flash de aplicar avisa del bloqueo" do
    add_item(@product, 6)

    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    assert_match(/Quedó bloqueada: quita la promoción si necesitas cambiar algo/, response.body)
  end

  # --- Regalos --------------------------------------------------------------

  test "el regalo entra como partida marcada y el aviso lo dice" do
    gift_product = make_product("SOLDADURA DEVCON", 68)
    @promo.promotion_tiers.last.promotion_gifts.create!(product: gift_product, quantity: 8)
    add_item(@product, 6)

    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    gift = @order.order_items.reload.find(&:gift?)
    assert_equal gift_product.id, gift.product_id
    assert_match(/partida de regalo/, response.body)
    assert_match(/Regalo/, response.body)
  end

  test "quitar la promoción se lleva el regalo" do
    gift_product = make_product("SOLDADURA DEVCON", 68)
    @promo.promotion_tiers.last.promotion_gifts.create!(product: gift_product, quantity: 8)
    add_item(@product, 6)
    post order_promotions_path(@order), params: { promotion_id: @promo.id }
    assert @order.order_items.reload.any?(&:gift?)

    delete order_promotion_path(@order, @promo)

    assert_empty @order.order_items.reload.select(&:gift?)
  end

  # --- Pedido ya transmitido ------------------------------------------------

  test "un pedido transmitido no acepta cambios de promoción" do
    add_item(@product, 6)
    @order.update!(status: "transmitted", erp_folio: "1A0007", transmitted_at: Time.current)

    post order_promotions_path(@order), params: { promotion_id: @promo.id }

    assert_response :forbidden
  end
end
