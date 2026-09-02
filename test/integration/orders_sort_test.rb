require "test_helper"

# Ordenamiento del reporte de pedidos capturados, por cualquier columna.
class OrdersSortTest < ActionDispatch::IntegrationTest
  setup do
    @round = BusinessRound.create!(erp_round_id: 960, name: "Rueda 960", active: true)
    Setting.instance.update!(selected_round_erp_id: 960, selected_round_name: "Rueda 960")
    @sup   = Supplier.create!(erp_supplier_id: 960, name: "PROVEEDOR")
    @other = Supplier.create!(erp_supplier_id: 961, name: "OTRO")

    @server = User.create!(erp_person_id: 960, username: "srv960", password: "secret123",
                           role: "server", active: true)
    @ana  = User.create!(erp_person_id: 961, username: "ana", password: "secret123",
                         role: "capturista", name: "ANA", paternal_surname: "ZAPATA", active: true)
    @beto = User.create!(erp_person_id: 962, username: "beto", password: "secret123",
                         role: "capturista", name: "BETO", paternal_surname: "ALVAREZ", active: true)

    @v1 = Salesperson.create!(erp_salesperson_id: 1, name: "ZULEMA")
    @v2 = Salesperson.create!(erp_salesperson_id: 2, name: "ARTURO")
    @c1 = Client.create!(erp_client_key: "CLI1", name: "Uno", commercial_name: "ZAPATERIA", salesperson: @v1)
    @c2 = Client.create!(erp_client_key: "CLI2", name: "Dos", commercial_name: "ABARROTES", salesperson: @v2)

    @p1 = product!(960_001, @sup, 100)
    @p2 = product!(960_002, @other, 50)
  end

  def product!(erp_id, supplier, price)
    p = Product.create!(erp_product_id: erp_id, description: "PROD #{erp_id}", max_discount: 50)
    Price.create!(product: p, credit_wholesale_price: price, tax_rate: 0)
    ProductSupplier.create!(product: p, supplier: supplier)
    p
  end

  # `created_at` explícito: el orden por fecha se prueba con marcas distintas,
  # y creadas en el mismo segundo empatarían.
  def order!(user:, client:, folio:, status: "captured", created: Time.current, items: [])
    o = Order.create!(user: user, business_round: @round, client: client, kind: "remission",
                      status: status, local_folio: folio)
    o.update_column(:created_at, created)
    items.each_with_index do |(product, qty), i|
      o.order_items.create!(product: product, position: i + 1, quantity: qty,
                            unit_price: product.price.credit_wholesale_price,
                            discount_percent: 0, tax_rate: 0, code: product.erp_code,
                            description: product.description, unit: "PZA")
    end
    o
  end

  def folios(response_body)
    response_body.scan(/RN-\d{6}/).uniq
  end

  # --- Por defecto ---------------------------------------------------------

  test "sin parámetros, lo más reciente primero" do
    order!(user: @ana, client: @c1, folio: "RN-000001", created: 3.hours.ago)
    order!(user: @ana, client: @c1, folio: "RN-000002", created: 1.hour.ago)
    login_as "srv960"

    get captured_orders_report_path

    assert_equal %w[RN-000002 RN-000001], folios(response.body)
  end

  # --- Cada columna --------------------------------------------------------

  test "ordena por capturista, por nombre completo" do
    order!(user: @ana, client: @c1, folio: "RN-000001")   # ANA ZAPATA
    order!(user: @beto, client: @c1, folio: "RN-000002")  # BETO ALVAREZ
    login_as "srv960"

    get captured_orders_report_path(sort: "user", dir: "asc")
    assert_equal %w[RN-000001 RN-000002], folios(response.body), "ANA antes que BETO"

    get captured_orders_report_path(sort: "user", dir: "desc")
    assert_equal %w[RN-000002 RN-000001], folios(response.body)
  end

  test "ordena por fecha" do
    order!(user: @ana, client: @c1, folio: "RN-000001", created: 3.hours.ago)
    order!(user: @ana, client: @c1, folio: "RN-000002", created: 1.hour.ago)
    login_as "srv960"

    get captured_orders_report_path(sort: "date", dir: "asc")

    assert_equal %w[RN-000001 RN-000002], folios(response.body)
  end

  # Hora y fecha salen de la misma marca de tiempo: ordenan igual.
  test "la hora ordena por la misma columna que la fecha" do
    order!(user: @ana, client: @c1, folio: "RN-000001", created: 3.hours.ago)
    order!(user: @ana, client: @c1, folio: "RN-000002", created: 1.hour.ago)
    login_as "srv960"

    get captured_orders_report_path(sort: "time", dir: "asc")

    assert_equal %w[RN-000001 RN-000002], folios(response.body)
  end

  test "ordena por cliente, por nombre comercial" do
    order!(user: @ana, client: @c1, folio: "RN-000001")  # ZAPATERIA
    order!(user: @ana, client: @c2, folio: "RN-000002")  # ABARROTES
    login_as "srv960"

    get captured_orders_report_path(sort: "client", dir: "asc")

    assert_equal %w[RN-000002 RN-000001], folios(response.body), "ABARROTES antes que ZAPATERIA"
  end

  test "ordena por vendedor" do
    order!(user: @ana, client: @c1, folio: "RN-000001")  # ZULEMA
    order!(user: @ana, client: @c2, folio: "RN-000002")  # ARTURO
    login_as "srv960"

    get captured_orders_report_path(sort: "salesperson", dir: "asc")

    assert_equal %w[RN-000002 RN-000001], folios(response.body)
  end

  test "ordena por clave local" do
    order!(user: @ana, client: @c1, folio: "RN-000009", created: 3.hours.ago)
    order!(user: @ana, client: @c1, folio: "RN-000001", created: 1.hour.ago)
    login_as "srv960"

    get captured_orders_report_path(sort: "folio", dir: "asc")

    assert_equal %w[RN-000001 RN-000009], folios(response.body)
  end

  # Un borrador no tiene folio todavía y la celda muestra "(borrador)".
  # Ordenando por la columna cruda quedaban en NULL y —con NULLS LAST— clavados
  # al final en las DOS direcciones: al invertir el orden no se movían y la
  # columna parecía no funcionar. Se ordena por el TEXTO VISIBLE.
  test "los borradores se mueven al invertir el orden por clave local" do
    order!(user: @ana, client: @c1, folio: "RN-000005")
    order!(user: @ana, client: @c1, folio: "RN-000001")
    Order.create!(user: @ana, business_round: @round, client: @c1, kind: "remission")
    login_as "srv960"

    get captured_orders_report_path(sort: "folio", dir: "asc")
    asc = response.body.scan(/RN-\d{6}|\(borrador\)/)

    get captured_orders_report_path(sort: "folio", dir: "desc")
    desc = response.body.scan(/RN-\d{6}|\(borrador\)/)

    assert_equal asc.reverse, desc, "invertir el orden debe invertir TODA la columna"
    assert_equal "(borrador)", asc.first, "el borrador se ordena por lo que muestra la celda"
    assert_equal "(borrador)", desc.last
  end

  test "ordena por renglones" do
    order!(user: @ana, client: @c1, folio: "RN-000001", items: [ [ @p1, 1 ] ])
    order!(user: @ana, client: @c1, folio: "RN-000002", items: [ [ @p1, 1 ], [ @p2, 1 ] ])
    login_as "srv960"

    get captured_orders_report_path(sort: "items", dir: "asc")
    assert_equal %w[RN-000001 RN-000002], folios(response.body)

    get captured_orders_report_path(sort: "items", dir: "desc")
    assert_equal %w[RN-000002 RN-000001], folios(response.body)
  end

  test "ordena por total" do
    order!(user: @ana, client: @c1, folio: "RN-000001", items: [ [ @p2, 1 ] ])   # 50
    order!(user: @ana, client: @c1, folio: "RN-000002", items: [ [ @p1, 3 ] ])   # 300
    login_as "srv960"

    get captured_orders_report_path(sort: "total", dir: "desc")

    assert_equal %w[RN-000002 RN-000001], folios(response.body)
  end

  # Por el flujo, no alfabético: alfabético daría capturado/borrador/transmitido.
  test "ordena por estatus siguiendo el flujo del pedido" do
    order!(user: @ana, client: @c1, folio: "RN-000003", status: "transmitted")
    order!(user: @ana, client: @c1, folio: "RN-000002", status: "captured")
    borrador = Order.create!(user: @ana, business_round: @round, client: @c1, kind: "remission")
    login_as "srv960"

    get captured_orders_report_path(sort: "status", dir: "asc")

    posiciones = response.body
    assert_operator posiciones.index("Borrador"), :<, posiciones.index("Capturado")
    assert_operator posiciones.index("Capturado"), :<, posiciones.index("Transmitido")
    assert borrador.persisted?
  end

  # --- Lo que protege ------------------------------------------------------

  # El parámetro viene de la URL: si se interpolara, aquí habría inyección.
  test "una columna inventada cae al orden por omisión, sin reventar" do
    order!(user: @ana, client: @c1, folio: "RN-000001", created: 3.hours.ago)
    order!(user: @ana, client: @c1, folio: "RN-000002", created: 1.hour.ago)
    login_as "srv960"

    get captured_orders_report_path(sort: "orders.id; DROP TABLE orders --", dir: "asc")

    assert_response :success
    # La LLAVE cae a la de omisión (fecha); la dirección pedida sí se respeta
    # porque "asc" es válida — de ahí el más viejo primero.
    assert_equal %w[RN-000001 RN-000002], folios(response.body)
    assert Order.count.positive?, "la tabla sigue viva"
  end

  test "una dirección inventada cae a descendente" do
    order!(user: @ana, client: @c1, folio: "RN-000001", created: 3.hours.ago)
    order!(user: @ana, client: @c1, folio: "RN-000002", created: 1.hour.ago)
    login_as "srv960"

    get captured_orders_report_path(sort: "date", dir: "ASC; DELETE FROM orders --")

    assert_response :success
    assert_equal %w[RN-000002 RN-000001], folios(response.body)
  end

  # El orden se aplica en SQL, antes de paginar: si solo ordenara la página,
  # la primera seguiría trayendo los mismos pedidos, acomodados entre sí.
  test "el orden manda sobre TODO el conjunto, no sobre la página" do
    30.times { |i| order!(user: @ana, client: @c1, folio: "RN-#{format('%06d', i + 1)}", created: (30 - i).hours.ago) }
    login_as "srv960"

    get captured_orders_report_path(sort: "folio", dir: "desc", per_page: 25)

    # El folio más alto es el más reciente; con orden descendente debe estar en
    # la primera página aunque por fecha sea el último.
    assert_includes folios(response.body), "RN-000030"
    assert_not_includes folios(response.body), "RN-000001"
  end

  test "el orden sobrevive al cambio de página" do
    30.times { |i| order!(user: @ana, client: @c1, folio: "RN-#{format('%06d', i + 1)}") }
    login_as "srv960"

    get captured_orders_report_path(sort: "folio", dir: "asc", per_page: 25)

    assert_match(/sort=folio/, response.body, "los enlaces del paginador conservan el orden")
    assert_match(/dir=asc/, response.body)
  end

  # Un pedido sin vendedor no debe encabezar la tabla solo por estar vacío.
  test "los nulos van al final en las dos direcciones" do
    sin_vendedor = Client.create!(erp_client_key: "CLI3", name: "Sin vendedor")
    order!(user: @ana, client: sin_vendedor, folio: "RN-000001")
    order!(user: @ana, client: @c1, folio: "RN-000002")
    login_as "srv960"

    get captured_orders_report_path(sort: "salesperson", dir: "asc")
    assert_equal %w[RN-000002 RN-000001], folios(response.body)

    get captured_orders_report_path(sort: "salesperson", dir: "desc")
    assert_equal %w[RN-000002 RN-000001], folios(response.body), "el nulo sigue al final"
  end

  # --- Con filtro de partida activo ----------------------------------------
  # La pantalla ya no muestra el total del PEDIDO sino el de las partidas que
  # coinciden con el filtro. El orden tiene que seguir a lo que se ve: ordenar
  # por el total del pedido mientras la celda enseña otro número sería
  # incomprensible.

  test "con filtro de proveedor, ordena por el importe de las partidas que coinciden" do
    # RN-000001: poco del proveedor filtrado, mucho de otro → pedido grande.
    order!(user: @ana, client: @c1, folio: "RN-000001", items: [ [ @p1, 1 ], [ @p2, 20 ] ])
    # RN-000002: mucho del proveedor filtrado → pedido chico, pero gana en @sup.
    order!(user: @ana, client: @c1, folio: "RN-000002", items: [ [ @p1, 5 ] ])
    login_as "srv960"

    # Sin filtro manda el total del pedido: el 1 (100 + 1000) va primero.
    get captured_orders_report_path(sort: "total", dir: "desc")
    assert_equal %w[RN-000001 RN-000002], folios(response.body)

    # Con el proveedor de @p1 filtrado, lo que se compara es 500 contra 100.
    get captured_orders_report_path(sort: "total", dir: "desc", supplier_id: @sup.id)
    assert_equal %w[RN-000002 RN-000001], folios(response.body),
                 "el orden sigue al importe que la pantalla muestra"
  end

  test "con filtro, los renglones también son los que coinciden" do
    order!(user: @ana, client: @c1, folio: "RN-000001", items: [ [ @p1, 1 ], [ @p2, 1 ] ])
    order!(user: @ana, client: @c1, folio: "RN-000002", items: [ [ @p1, 1 ] ])
    login_as "srv960"

    # Los dos tienen 1 renglón del proveedor filtrado: empatan, y el desempate
    # por id los deja estables en vez de bailar entre peticiones.
    get captured_orders_report_path(sort: "items", dir: "desc", supplier_id: @sup.id)
    primero = folios(response.body)

    get captured_orders_report_path(sort: "items", dir: "desc", supplier_id: @sup.id)
    assert_equal primero, folios(response.body), "el orden es estable entre peticiones"
  end

  # --- La cabecera ---------------------------------------------------------

  test "la columna activa se anuncia con aria-sort" do
    order!(user: @ana, client: @c1, folio: "RN-000001")
    login_as "srv960"

    get captured_orders_report_path(sort: "total", dir: "asc")

    assert_select "th[aria-sort=ascending]", 1
    assert_select "th[aria-sort=none]", { minimum: 5 }, "las demás columnas se anuncian sin orden"
  end

  test "el clic siguiente sobre la misma columna invierte el sentido" do
    order!(user: @ana, client: @c1, folio: "RN-000001")
    login_as "srv960"

    get captured_orders_report_path(sort: "total", dir: "asc")

    assert_select "th a[href*='sort=total'][href*='dir=desc']"
  end

  test "los encabezados conservan los filtros activos" do
    order!(user: @ana, client: @c1, folio: "RN-000001")
    login_as "srv960"

    get captured_orders_report_path(status: "captured")

    assert_select "th a[href*='status=captured']"
  end
end
