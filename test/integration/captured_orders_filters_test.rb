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

  # Folio correlativo: con `rand` dos pedidos podían chocar contra el índice
  # único de local_folio y el test fallaba de forma intermitente.
  def next_folio
    @folio_seq = (@folio_seq || 0) + 1
    format("RN-%06d", @folio_seq)
  end

  def order!(user:, client:, status: "captured", created_at: Time.current, product: nil)
    o = Order.create!(user: user, business_round: @round, client: client, kind: "remission",
                      status: status,
                      local_folio: (status == "draft" ? nil : next_folio),
                      erp_folio: (status == "transmitted" ? "1A0001" : nil))
    o.order_items.create!(position: 1, product: product, quantity: 1, unit_price: 100,
                          tax_rate: 16, discount_percent: 0)
    o.update_column(:created_at, created_at)
    o
  end

  # El renglón de "No hay pedidos capturados" también es un <tr>: se descarta
  # por su celda con colspan, o un listado vacío contaría como una fila.
  def data_rows
    css_select("tbody tr").count { |tr| tr.css("td[colspan]").empty? }
  end

  # --- Filtros del pedido --------------------------------------------------

  test "usuario crea acota el listado y el resumen" do
    order!(user: @ana,  client: @c1)
    order!(user: @beto, client: @c1)
    order!(user: @beto, client: @c2)
    login_as("srv990")

    get captured_orders_report_path(user_id: @beto.id)
    assert_response :success
    assert_equal 2, data_rows

    summary = OrdersFilter.new(user_id: @beto.id).apply_without_status(Order.all).totals_by_status
    assert_equal 2, summary["captured"][:count], "el resumen se acota igual que la tabla"
  end

  test "cliente y vendedor acotan el listado" do
    order!(user: @ana, client: @c1)
    order!(user: @ana, client: @c2)
    login_as("srv990")

    get captured_orders_report_path(client_id: @c2.id)
    assert_equal 1, data_rows

    get captured_orders_report_path(salesperson_id: @v1.id)
    assert_equal 1, data_rows, "el vendedor es el del cliente del pedido"
  end

  test "el rango de fechas usa el día LOCAL que muestra la pantalla" do
    # 19:00 local del día 10 se guarda como 01:00 UTC del 11: filtrar en UTC
    # dejaría fuera al pedido que la columna Fecha muestra como día 10.
    tarde = ::Time.new(2026, 8, 10, 19, 0, 0)
    order!(user: @ana, client: @c1, created_at: tarde)
    order!(user: @ana, client: @c1, created_at: ::Time.new(2026, 8, 12, 9, 0, 0))
    login_as("srv990")

    get captured_orders_report_path(from: "2026-08-10", to: "2026-08-10")
    assert_equal 1, data_rows

    get captured_orders_report_path(from: "2026-08-11")
    assert_equal 1, data_rows, "solo el del día 12"

    get captured_orders_report_path(from: "2026-08-10", to: "2026-08-12")
    assert_equal 2, data_rows
  end

  # El día se cierra con un rango excluyente hasta el inicio del siguiente: con
  # las 23:59:59 exactas, los microsegundos de Postgres dejaban fuera lo
  # capturado en el último segundo del día que la pantalla sí muestra.
  test "el último segundo del día final entra en el rango" do
    o = order!(user: @ana, client: @c1)
    o.update_column(:created_at, ::Time.new(2026, 8, 10, 23, 59, 59.5))
    login_as("srv990")

    get captured_orders_report_path(from: "2026-08-10", to: "2026-08-10")
    assert_equal 1, data_rows, "23:59:59.5 sigue siendo del día 10"
  end

  # Una página que ya no existe (marcador viejo, o la lista encogió) daba la
  # pantalla de error de Rails en plena laptop del evento.
  test "una página fuera de rango redirige en vez de reventar" do
    3.times { order!(user: @ana, client: @c1) }
    login_as("srv990")

    get captured_orders_report_path(page: 99)
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_equal 3, data_rows
  end

  # Con el hash crudo de la petición, un `?host=` hacía que Rails generara los
  # enlaces del paginador como URLs ABSOLUTAS a ese dominio.
  test "un host inyectado en la URL no se cuela a los enlaces del paginador" do
    30.times { order!(user: @ana, client: @c1) }
    login_as("srv990")

    get captured_orders_report_path(host: "sitio-ajeno.example.com")
    assert_response :success
    assert_no_match(/sitio-ajeno\.example\.com/, response.body)
  end

  test "el estado vacío distingue sin pedidos de sin coincidencias" do
    login_as("srv990")

    get captured_orders_report_path
    assert_match(/Todavía no hay pedidos capturados/, response.body)

    order!(user: @ana, client: @c1)
    get captured_orders_report_path(client_id: @c2.id)
    assert_match(/Ningún pedido coincide/, response.body)
    assert_match(/Quitar filtros/, response.body)
  end

  test "una fecha inválida se ignora en vez de reventar" do
    order!(user: @ana, client: @c1)
    login_as("srv990")

    get captured_orders_report_path(from: "no-es-fecha")
    assert_response :success
    assert_equal 1, data_rows
  end

  # --- Estatus: las tarjetas son el filtro ---------------------------------

  test "el estatus acota la tabla pero NO el resumen" do
    order!(user: @ana, client: @c1, status: "draft")
    2.times { order!(user: @ana, client: @c1, status: "captured") }
    login_as("srv990")

    get captured_orders_report_path(status: "draft")
    assert_equal 1, data_rows, "la tabla sí se acota"
    # El resumen conserva los tres estatus para poder saltar entre tarjetas.
    assert_match(/Capturado/, response.body)
    assert_select "a[href*=?]", "status=captured"
  end

  test "el resumen SÍ refleja los demás filtros" do
    order!(user: @ana,  client: @c1, status: "captured")
    order!(user: @beto, client: @c1, status: "captured")
    order!(user: @beto, client: @c1, status: "draft")
    login_as("srv990")

    summary = OrdersFilter.new(user_id: @beto.id).apply_without_status(Order.all).totals_by_status
    assert_equal 1, summary["captured"][:count], "solo los de BETO"
    assert_equal 1, summary["draft"][:count]
  end

  test "un estatus desconocido se ignora" do
    order!(user: @ana, client: @c1)
    login_as("srv990")

    get captured_orders_report_path(status: "inventado")
    assert_response :success
    assert_equal 1, data_rows
  end

  # --- Alcance por rol -----------------------------------------------------

  test "el capturista no puede filtrar hacia pedidos ajenos" do
    order!(user: @ana,  client: @c1)
    order!(user: @beto, client: @c1)
    login_as("ana991")

    get captured_orders_report_path(user_id: @beto.id)
    assert_response :success
    assert_equal 0, data_rows, "el filtro se aplica SOBRE su propio alcance"
  end

  test "el combo de usuario crea solo se ofrece al equipo-servidor" do
    order!(user: @ana, client: @c1)

    login_as("srv990")
    get captured_orders_report_path
    assert_select "input[name=?]", "user_id", 1

    login_as("ana991")
    get captured_orders_report_path
    assert_select "input[name=?]", "user_id", 0
  end

  # --- Filtros de PARTIDA (proveedor / marca / producto) -------------------
  # Regla del usuario: con uno activo, los importes que se muestran son los de
  # las partidas que COINCIDEN, no los del pedido completo.

  def build_catalog!
    @makita  = Supplier.create!(erp_supplier_id: 993, name: "MAKITA")
    @stihl   = Supplier.create!(erp_supplier_id: 994, name: "STIHL")
    @m_brand = Brand.create!(erp_brand_id: 993, name: "MARCA MAKITA")
    @disco   = Product.create!(erp_product_id: 19_163, description: "DISCO CRTE 7", brand: @m_brand, unit: "PZA")
    @motosi  = Product.create!(erp_product_id: 44_444, description: "MOTOSIERRA", unit: "PZA")
    ProductSupplier.create!(product: @disco,  supplier: @makita)
    ProductSupplier.create!(product: @motosi, supplier: @stihl)
  end

  # Pedido mixto: una partida MAKITA ($116) y una STIHL ($232).
  def mixed_kinds_order!
    o = Order.create!(user: @ana, business_round: @round, client: @c1, kind: "remission",
                      status: "captured", local_folio: next_folio)
    o.order_items.create!(position: 1, product: @disco,  quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0)
    o.order_items.create!(position: 2, product: @motosi, quantity: 2, unit_price: 100, tax_rate: 16, discount_percent: 0)
    o
  end

  test "el filtro de proveedor trae los pedidos que traen al menos una partida suya" do
    build_catalog!
    mixed_kinds_order!
    order!(user: @ana, client: @c1, product: @motosi)
    login_as("srv990")

    get captured_orders_report_path(supplier_id: @makita.id)
    assert_equal 1, data_rows, "solo el mixto trae MAKITA"

    get captured_orders_report_path(supplier_id: @stihl.id)
    assert_equal 2, data_rows
  end

  test "con filtro de proveedor el importe es el de SUS partidas, no el del pedido" do
    build_catalog!
    o = mixed_kinds_order!
    assert_in_delta 348, o.total, 0.01, "el pedido completo son $348"
    login_as("srv990")

    summary = OrdersFilter.new(supplier_id: @makita.id)
                          .then { |f| f.apply_without_status(Order.all).totals_by_status(f.matching_products) }
    assert_equal 1, summary["captured"][:count]
    assert_in_delta 116, summary["captured"][:total], 0.01, "solo la partida MAKITA"

    get captured_orders_report_path(supplier_id: @makita.id)
    assert_match(/\$116\.00/, response.body)
    assert_no_match(/\$348\.00/, response.body)
  end

  test "la pantalla avisa que los importes son de las partidas" do
    build_catalog!
    mixed_kinds_order!
    login_as("srv990")

    get captured_orders_report_path(supplier_id: @makita.id)
    assert_match(/Importes de las partidas de MAKITA/, response.body)

    # El producto se busca por texto: se enuncia distinto que un proveedor.
    get captured_orders_report_path(product_q: "019163")
    assert_match(/Importes de las partidas que coinciden con &quot;019163&quot;/, response.body)

    get captured_orders_report_path
    assert_no_match(/Importes de las partidas/, response.body)
  end

  # --- Autocompletado del filtro de producto -------------------------------

  test "el autocompletado sugiere productos por nombre y por código" do
    build_catalog!
    login_as("srv990")

    get product_options_report_path(q: "DISCO")
    assert_response :success
    assert_match(/DISCO CRTE 7/, response.body)
    assert_match(/019163/, response.body, "muestra el código a 6 dígitos")
    assert_match(/data-code="019163"/, response.body, "elegir escribe el código en el filtro")

    get product_options_report_path(q: "019163")
    assert_match(/DISCO CRTE 7/, response.body)
  end

  test "sin coincidencias el autocompletado lo dice" do
    build_catalog!
    login_as("srv990")

    get product_options_report_path(q: "NO EXISTE")
    assert_match(/Sin resultados/, response.body)
  end

  # El capturista solo ve productos de su universo: ofrecerle otros sería
  # sugerirle filtros que nunca podrían aparecer en sus pedidos.
  test "el autocompletado del capturista se acota a su universo" do
    build_catalog!
    BusinessRoundPerson.create!(business_round: @round, user: @ana, position: 1, supplier: @makita)
    login_as("ana991")

    get product_options_report_path(q: "DISCO")
    assert_match(/DISCO CRTE 7/, response.body, "el disco es del proveedor que tiene asignado")

    get product_options_report_path(q: "MOTOSIERRA")
    assert_match(/Sin resultados/, response.body, "la motosierra es de otro proveedor")
  end

  test "renglones también cuenta solo las partidas que coinciden" do
    build_catalog!
    mixed_kinds_order!   # 2 partidas, 1 de MAKITA
    login_as("srv990")

    get captured_orders_report_path(supplier_id: @makita.id)
    assert_select "tbody tr td:nth-last-child(3)", text: "1"
  end

  test "marca y producto filtran igual" do
    build_catalog!
    mixed_kinds_order!
    login_as("srv990")

    get captured_orders_report_path(brand_id: @m_brand.id)
    assert_equal 1, data_rows
    assert_match(/\$116\.00/, response.body)

    get captured_orders_report_path(product_q: "019163")
    assert_equal 1, data_rows, "busca por el código a 6 dígitos"

    get captured_orders_report_path(product_q: "MOTOSIERRA")
    assert_equal 1, data_rows
    assert_match(/\$232\.00/, response.body)
  end

  test "los filtros de partida se combinan entre sí (intersección)" do
    build_catalog!
    mixed_kinds_order!
    login_as("srv990")

    # MAKITA + su marca → coincide; MAKITA + producto de STIHL → nada.
    get captured_orders_report_path(supplier_id: @makita.id, brand_id: @m_brand.id)
    assert_equal 1, data_rows

    get captured_orders_report_path(supplier_id: @makita.id, product_q: "MOTOSIERRA")
    assert_equal 0, data_rows
  end

  test "un filtro de partida sin coincidencias deja el resumen en ceros" do
    build_catalog!
    mixed_kinds_order!
    login_as("srv990")

    get captured_orders_report_path(product_q: "NO EXISTE ESTE PRODUCTO")
    assert_response :success
    assert_equal 0, data_rows
  end

  # --- Enlaces -------------------------------------------------------------

  test "los enlaces del paginador conservan los filtros" do
    30.times { order!(user: @beto, client: @c1) }
    order!(user: @ana, client: @c1)
    login_as("srv990")

    get captured_orders_report_path(user_id: @beto.id)
    assert_equal 25, data_rows
    assert_select "a[href*=?]", "user_id=#{@beto.id}"

    get captured_orders_report_path(user_id: @beto.id, page: 2)
    assert_equal 5, data_rows, "la segunda página sigue filtrada"
  end

  test "el formulario de filtros no arrastra la página" do
    30.times { order!(user: @ana, client: @c1) }
    login_as("srv990")

    get captured_orders_report_path(page: 2)
    assert_select "form input[name=?]", "page", 0,
                  "filtrar debe regresar a la primera página"
  end

  test "limpiar filtros aparece solo cuando hay alguno activo" do
    order!(user: @ana, client: @c1)
    login_as("srv990")

    get captured_orders_report_path
    assert_no_match(/Limpiar filtros/, response.body)

    get captured_orders_report_path(client_id: @c1.id)
    assert_match(/Limpiar filtros/, response.body)
  end
end
