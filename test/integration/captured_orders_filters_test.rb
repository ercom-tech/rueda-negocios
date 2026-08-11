require "test_helper"

# Filtros del reporte "Pedidos capturados" (entrega 1: los que son del pedido
# — usuario crea, cliente, vendedor y fecha crea).
#
# Reglas que se fijan aquí:
#  · el filtro se aplica SOBRE el alcance por rol → un capturista no puede
#    filtrar hacia pedidos ajenos;
#  · el resumen refleja todos los filtros MENOS el de estatus (sus tarjetas
#    son ese filtro y deben seguir mostrando el panorama completo);
#  · los enlaces conservan los filtros y nunca arrastran `page`.
class CapturedOrdersFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @round = BusinessRound.create!(erp_round_id: 990, name: "Rueda 990", active: true)
    @v1    = Salesperson.create!(erp_salesperson_id: 991, name: "Vendedor Uno")
    @v2    = Salesperson.create!(erp_salesperson_id: 992, name: "Vendedor Dos")
    @c1    = Client.create!(erp_client_key: "CL991", name: "Cliente Uno", salesperson: @v1)
    @c2    = Client.create!(erp_client_key: "CL992", name: "Cliente Dos", salesperson: @v2)
    @ana   = User.create!(erp_person_id: 991, username: "ana991", password: "secret123",
                          role: "capturista", active: true, name: "ANA")
    @beto  = User.create!(erp_person_id: 992, username: "beto992", password: "secret123",
                          role: "capturista", active: true, name: "BETO")
    User.create!(erp_person_id: 990, username: "srv990", password: "secret123",
                 role: "server", active: true)
    Setting.instance.update!(selected_round_erp_id: 990, selected_round_name: "Rueda 990")
  end

  def order!(user:, client:, status: "captured", created_at: Time.current)
    o = Order.create!(user: user, business_round: @round, client: client, kind: "remission",
                      status: status,
                      local_folio: (status == "draft" ? nil : "RN-#{format('%06d', rand(1_000_000))}"),
                      erp_folio: (status == "transmitted" ? "1A0001" : nil))
    o.order_items.create!(position: 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0)
    o.update_column(:created_at, created_at)
    o
  end

  def login(username) = post(login_path, params: { username: username, password: "secret123" })

  # El renglón de "No hay pedidos capturados" también es un <tr>: se descarta
  # por su celda con colspan, o un listado vacío contaría como una fila.
  def filas
    css_select("tbody tr").count { |tr| tr.css("td[colspan]").empty? }
  end

  # --- Filtros del pedido --------------------------------------------------

  test "usuario crea acota el listado y el resumen" do
    order!(user: @ana,  client: @c1)
    order!(user: @beto, client: @c1)
    order!(user: @beto, client: @c2)
    login("srv990")

    get captured_orders_report_path(user_id: @beto.id)
    assert_response :success
    assert_equal 2, filas

    resumen = OrdersFilter.new(user_id: @beto.id).apply_without_status(Order.all).totals_by_status
    assert_equal 2, resumen["captured"][:count], "el resumen se acota igual que la tabla"
  end

  test "cliente y vendedor acotan el listado" do
    order!(user: @ana, client: @c1)
    order!(user: @ana, client: @c2)
    login("srv990")

    get captured_orders_report_path(client_id: @c2.id)
    assert_equal 1, filas

    get captured_orders_report_path(salesperson_id: @v1.id)
    assert_equal 1, filas, "el vendedor es el del cliente del pedido"
  end

  test "el rango de fechas usa el día LOCAL que muestra la pantalla" do
    # 19:00 local del día 10 se guarda como 01:00 UTC del 11: filtrar en UTC
    # dejaría fuera al pedido que la columna Fecha muestra como día 10.
    tarde = ::Time.new(2026, 8, 10, 19, 0, 0)
    order!(user: @ana, client: @c1, created_at: tarde)
    order!(user: @ana, client: @c1, created_at: ::Time.new(2026, 8, 12, 9, 0, 0))
    login("srv990")

    get captured_orders_report_path(from: "2026-08-10", to: "2026-08-10")
    assert_equal 1, filas

    get captured_orders_report_path(from: "2026-08-11")
    assert_equal 1, filas, "solo el del día 12"

    get captured_orders_report_path(from: "2026-08-10", to: "2026-08-12")
    assert_equal 2, filas
  end

  test "una fecha inválida se ignora en vez de reventar" do
    order!(user: @ana, client: @c1)
    login("srv990")

    get captured_orders_report_path(from: "no-es-fecha")
    assert_response :success
    assert_equal 1, filas
  end

  # --- Estatus: las tarjetas son el filtro ---------------------------------

  test "el estatus acota la tabla pero NO el resumen" do
    order!(user: @ana, client: @c1, status: "draft")
    2.times { order!(user: @ana, client: @c1, status: "captured") }
    login("srv990")

    get captured_orders_report_path(status: "draft")
    assert_equal 1, filas, "la tabla sí se acota"
    # El resumen conserva los tres estatus para poder saltar entre tarjetas.
    assert_match(/Capturado/, response.body)
    assert_select "a[href*=?]", "status=captured"
  end

  test "el resumen SÍ refleja los demás filtros" do
    order!(user: @ana,  client: @c1, status: "captured")
    order!(user: @beto, client: @c1, status: "captured")
    order!(user: @beto, client: @c1, status: "draft")
    login("srv990")

    resumen = OrdersFilter.new(user_id: @beto.id).apply_without_status(Order.all).totals_by_status
    assert_equal 1, resumen["captured"][:count], "solo los de BETO"
    assert_equal 1, resumen["draft"][:count]
  end

  test "un estatus desconocido se ignora" do
    order!(user: @ana, client: @c1)
    login("srv990")

    get captured_orders_report_path(status: "inventado")
    assert_response :success
    assert_equal 1, filas
  end

  # --- Alcance por rol -----------------------------------------------------

  test "el capturista no puede filtrar hacia pedidos ajenos" do
    order!(user: @ana,  client: @c1)
    order!(user: @beto, client: @c1)
    login("ana991")

    get captured_orders_report_path(user_id: @beto.id)
    assert_response :success
    assert_equal 0, filas, "el filtro se aplica SOBRE su propio alcance"
  end

  test "el combo de usuario crea solo se ofrece al equipo-servidor" do
    order!(user: @ana, client: @c1)

    login("srv990")
    get captured_orders_report_path
    assert_select "input[name=?]", "user_id", 1

    login("ana991")
    get captured_orders_report_path
    assert_select "input[name=?]", "user_id", 0
  end

  # --- Enlaces -------------------------------------------------------------

  test "los enlaces del paginador conservan los filtros" do
    30.times { order!(user: @beto, client: @c1) }
    order!(user: @ana, client: @c1)
    login("srv990")

    get captured_orders_report_path(user_id: @beto.id)
    assert_equal 25, filas
    assert_select "a[href*=?]", "user_id=#{@beto.id}"

    get captured_orders_report_path(user_id: @beto.id, page: 2)
    assert_equal 5, filas, "la segunda página sigue filtrada"
  end

  test "el formulario de filtros no arrastra la página" do
    30.times { order!(user: @ana, client: @c1) }
    login("srv990")

    get captured_orders_report_path(page: 2)
    assert_select "form input[name=?]", "page", 0,
                  "filtrar debe regresar a la primera página"
  end

  test "limpiar filtros aparece solo cuando hay alguno activo" do
    order!(user: @ana, client: @c1)
    login("srv990")

    get captured_orders_report_path
    assert_no_match(/Limpiar filtros/, response.body)

    get captured_orders_report_path(client_id: @c1.id)
    assert_match(/Limpiar filtros/, response.body)
  end
end
