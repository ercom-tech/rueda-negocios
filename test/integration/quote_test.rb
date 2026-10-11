require "test_helper"

# El Cotizador de la captura: el botón junto al buscador, el modal y su
# contenido. El cálculo se prueba en test/services/promotions/quote_test.rb.
class QuoteTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 9411, username: "cap_qt", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 9411, name: "Rueda QT", active: true)
    Setting.instance.update!(selected_round_erp_id: 9411, selected_round_name: "Rueda QT")
    @client   = Client.create!(erp_client_key: "QT01", name: "Cliente QT")
    @supplier = Supplier.create!(erp_supplier_id: 9411, name: "FANDELI")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @supplier, position: 1)

    @product = make_product("LIJA AGUA C-99 NO. 180", 100, pieces_per_box: 10, erp_id: 7121)
    @order   = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    @promo   = Promotion.create!(erp_promotion_id: 3040, code: "BTI", name: "BTICINO - OAXACA 2026",
                                 starts_on: Date.new(2026, 8, 21), ends_on: 1.week.from_now.to_date)
    @promo.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CE", unit: "MXN",
                                   quantity_from: 10_000, quantity_to: 24_999, discount_percent: 7.85)
    @promo.promotion_products.create!(product: @product, discount_percent: 0)

    login_as "cap_qt"
  end

  def make_product(description, price, pieces_per_box: nil, erp_id: nil)
    product = Product.create!(erp_product_id: erp_id || rand(1_000_000..9_999_999), description:,
                              unit: "PZA", max_discount: 9, pieces_per_box:)
    Price.create!(product: product, credit_wholesale_price: price, tax_rate: 16)
    ProductSupplier.create!(product: product, supplier: @supplier)
    product
  end

  def add_item(product)
    @order.order_items.create!(product.to_order_item_attributes.merge(
      position: @order.next_item_position, quantity: 1, discount_percent: 0
    ))
  end

  test "la captura trae el botón, el cascarón del modal y la fila cotizable" do
    item = add_item(@product)

    get order_path(@order)

    assert_select "[data-controller~=quote] button[data-action='quote#open']:not([disabled])", text: /Cotizador/
    assert_select "#quote-modal turbo-frame#quote-frame"
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(item)}[data-quote-url=?]",
                  quote_order_order_item_path(@order, item)
  end

  test "el modal cotiza pieza y caja en cada escalón" do
    item = add_item(@product)

    get quote_order_order_item_path(@order, item)

    assert_response :success
    assert_select "turbo-frame#quote-frame"
    assert_match "BTICINO - OAXACA 2026", response.body
    assert_match "Vigente del 21/08/2026", response.body
    assert_match "007121", response.body
    assert_match "En la compra de entre $10,000 y $24,999", response.body
    assert_select "td", text: "7.85%"
    assert_select "td", text: "$1,000.00"  # caja sin promoción: 10 × $100
    assert_select "td", text: "$92.15"     # pieza con promoción
    assert_select "td", text: "$921.50"    # caja con promoción
    assert_select "th", text: "Por caja", count: 2
  end

  test "sin piezas por caja, el modal muestra solo la pieza" do
    @product.update!(pieces_per_box: nil)
    item = add_item(@product)

    get quote_order_order_item_path(@order, item)

    assert_select "th", text: "Por caja", count: 0
    assert_select "th", text: "Piezas en caja", count: 0
    assert_select "td", text: "$92.15"
  end

  test "vendido por pieza, los rótulos hablan de piezas" do
    item = add_item(@product)

    get quote_order_order_item_path(@order, item)

    assert_select "th", text: "Por pieza", count: 2
    assert_select "th", text: "Piezas en caja"
    assert_no_match "Se vende por", response.body
  end

  # 14ª auditoría: el 941101 se vende por CAJA de 100 anzuelos y su caja de la
  # ficha es de 10 cajitas. "Por pieza" sobre ese precio le decía al cliente un
  # precio 100 veces mayor por anzuelo.
  test "vendido por otra unidad, los rótulos no dicen pieza y nombran la unidad" do
    @product.update!(unit: "CAJA")
    item = add_item(@product)

    get quote_order_order_item_path(@order, item)

    assert_select "th", text: "Por unidad", count: 2
    assert_select "th", text: "Unidades en caja"
    assert_select "th", text: /pieza/i, count: 0
    assert_match(/Se vende por\s*<span[^>]*>CAJA</, response.body)
  end

  # FANDELI: dos escalones al mismo % y el segundo con regalo.
  test "el escalón con regalo lo dice" do
    tier = @promo.promotion_tiers.create!(erp_consecutive: 2, condition_kind: "CM", unit: "MXN",
                                          quantity_from: 25_000, discount_percent: 7.85)
    tier.promotion_gifts.create!(product: make_product("REGALO", 10), quantity: 1)
    item = add_item(@product)

    get quote_order_order_item_path(@order, item)

    assert_select "tbody tr", count: 2
    assert_select "tbody tr:nth-child(1) td:first-child", text: /\A\s*En la compra de entre[^+]*\z/
    assert_select "tbody tr:nth-child(2) td:first-child", text: /En la compra mínima de \$25,000\s*\+ regalo/
  end

  # Los grupos "Sin/Con promoción" son colgroup para el lector de pantalla, y
  # las esquinas vacías no son encabezados.
  test "los encabezados de grupo se anuncian como grupo" do
    item = add_item(@product)

    get quote_order_order_item_path(@order, item)

    assert_select "thead th[scope=colgroup]", count: 2
    assert_select "thead th:empty", count: 0
  end

  test "un producto sin promoción lo dice, sin tabla" do
    item = add_item(make_product("MARTILLO", 250))

    get quote_order_order_item_path(@order, item)

    assert_select "table", count: 0
    assert_select "#quote-title", text: "Sin promoción"
    assert_no_match "Promoción de la rueda", response.body
    assert_match "no está en ninguna promoción vigente", response.body
    # "Antes de descuentos": no afirma lo que se cobra, que puede llevar un
    # descuento manual (14ª auditoría).
    assert_match "su precio es de $250.00 por pieza, antes de descuentos.", response.body
  end

  test "los regalos no son cotizables" do
    gift = add_item(make_product("REGALO", 50))
    gift.update_columns(gift: true)

    get order_path(@order)

    assert_select "tr##{ActionView::RecordIdentifier.dom_id(gift)}"
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(gift)}[data-quote-url]", count: 0
  end

  # Es lectura: se puede cotizar mientras corre un sync, como ver una promoción.
  test "cotizar no se pausa durante un sync" do
    item = add_item(@product)
    SyncRun.create!(kind: "down", status: "running", pid: Process.pid, started_at: Time.current)

    get quote_order_order_item_path(@order, item)

    assert_response :success
  end

  test "solo se cotizan partidas del pedido" do
    other = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    foreign = other.order_items.create!(@product.to_order_item_attributes.merge(position: 1, quantity: 1,
                                                                                 discount_percent: 0))

    get quote_order_order_item_path(@order, foreign)

    assert_response :not_found
  end
end
