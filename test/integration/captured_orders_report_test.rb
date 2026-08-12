require "test_helper"

# Reporte "Pedidos capturados": resumen por estatus + paginador. El MISMO
# reporte sirve a los dos roles con distinto alcance — el capturista solo ve
# los suyos, y su resumen y su paginador tienen que estar acotados igual que
# su tabla.
class CapturedOrdersReportTest < ActionDispatch::IntegrationTest
  setup do
    @round  = BusinessRound.create!(erp_round_id: 980, name: "Rueda 980", active: true)
    @client = Client.create!(erp_client_key: "C980", name: "Cliente 980")
    @cap    = User.create!(erp_person_id: 981, username: "cap981", password: "secret123",
                           role: "capturista", active: true)
    @otro   = User.create!(erp_person_id: 982, username: "cap982", password: "secret123",
                           role: "capturista", active: true)
    User.create!(erp_person_id: 980, username: "srv980", password: "secret123",
                 role: "server", active: true)
    Setting.instance.update!(selected_round_erp_id: 980, selected_round_name: "Rueda 980")
  end

  # Folio de prueba correlativo: con `rand` dos pedidos podían chocar contra el
  # índice único de local_folio y el test fallaba de forma intermitente.
  def next_folio
    @folio_seq = (@folio_seq || 0) + 1
    format("RN-%06d", @folio_seq)
  end

  # Pedido con una partida de $100 + 16% = $116 (sin descuento).
  def order!(user:, status: "captured", items: 1)
    o = Order.create!(user: user, business_round: @round, client: @client, kind: "remission",
                      status: status,
                      local_folio: (status == "draft" ? nil : next_folio),
                      erp_folio: (status == "transmitted" ? "1A0001" : nil))
    items.times { |i| o.order_items.create!(position: i + 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0) }
    o
  end

  def login(username)
    post login_path, params: { username: username, password: "secret123" }
  end

  # --- Resumen por estatus ------------------------------------------------

  test "el resumen suma cantidad e importe por estatus" do
    2.times { order!(user: @cap, status: "draft") }
    3.times { order!(user: @cap, status: "captured", items: 2) }
    login("srv980")

    get captured_orders_report_path
    assert_response :success

    summary = Order.totals_by_status
    assert_equal 2, summary["draft"][:count]
    assert_equal 232, summary["draft"][:total],    "2 pedidos × 1 partida de $116"
    assert_equal 3, summary["captured"][:count]
    assert_equal 696, summary["captured"][:total], "3 pedidos × 2 partidas de $116"
  end

  test "el resumen incluye los tres estatus aunque vengan en cero" do
    order!(user: @cap, status: "captured")

    summary = Order.totals_by_status
    assert_equal %w[draft captured transmitted].sort, summary.keys.sort
    assert_equal 0, summary["transmitted"][:count]
    assert_equal 0, summary["transmitted"][:total]
  end

  test "el importe respeta descuento e IVA de cada partida" do
    brand   = Brand.create!(erp_brand_id: 980, name: "Marca 980")
    product = Product.create!(erp_product_id: 980_001, description: "P", brand: brand,
                              unit: "PZA", max_discount: 10)
    o = Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission",
                      status: "captured", local_folio: "RN-000999")
    o.order_items.create!(position: 1, product: product, quantity: 2, unit_price: 100,
                          tax_rate: 16, discount_percent: 10)

    # 2 × 100 = 200 − 10% = 180 + 16% = 208.80 (igual que OrderItem#total)
    assert_in_delta 208.80, Order.totals_by_status["captured"][:total], 0.01
    assert_in_delta o.total, Order.totals_by_status["captured"][:total], 0.01
  end

  test "el capturista solo resume SUS pedidos" do
    order!(user: @cap,  status: "captured")
    order!(user: @otro, status: "captured")
    order!(user: @otro, status: "captured")

    assert_equal 3, Order.totals_by_status["captured"][:count], "sin acotar son todos"
    assert_equal 1, @cap.orders.totals_by_status["captured"][:count], "acotado al capturista"
  end

  test "el reporte del capturista no muestra pedidos ajenos" do
    order!(user: @cap,  status: "captured")
    order!(user: @otro, status: "captured")
    login("cap981")

    get captured_orders_report_path
    assert_response :success
    assert_select "tbody tr", 1
  end

  # --- Paginador -----------------------------------------------------------

  test "con más de una página aparece la navegación y la segunda trae el resto" do
    30.times { order!(user: @cap) }
    login("srv980")

    get captured_orders_report_path
    assert_select "tbody tr", 25
    assert_select "nav[aria-label=?] a", "Paginación"

    get captured_orders_report_path(page: 2)
    assert_select "tbody tr", 5
  end

  test "el conteo se muestra aunque haya una sola página" do
    3.times { order!(user: @cap) }
    login("srv980")

    get captured_orders_report_path
    assert_match(/3 pedidos/, response.body)
    assert_no_match(/Siguiente/, response.body, "sin más páginas no hay navegación")
  end

  test "per_page cambia el tamaño de página" do
    30.times { order!(user: @cap) }
    login("srv980")

    get captured_orders_report_path(per_page: 50)
    assert_select "tbody tr", 30
  end

  test "un per_page fuera de la lista cae al default" do
    30.times { order!(user: @cap) }
    login("srv980")

    get captured_orders_report_path(per_page: 5000)
    assert_select "tbody tr", 25
  end

  # Si los enlaces solo llevaran `page:`, cualquier filtro de la URL se
  # perdería al cambiar de página (y los filtros ya están en el backlog).
  test "los enlaces del paginador conservan los demás parámetros" do
    30.times { order!(user: @cap) }
    login("srv980")

    get captured_orders_report_path(per_page: 25, page: 1)
    assert_select "a[href*=?]", "per_page=25"
  end
end
