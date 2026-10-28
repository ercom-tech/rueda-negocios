require "test_helper"

# Reporte "Cotizaciones capturadas" (decisión del usuario 2026-10-27): la
# misma estructura del de pedidos capturados —filtros, resumen por estatus,
# orden y paginación— sobre las cotizaciones, con lo que cambia: el cliente
# genérico, los dos estatus (Borrador y Guardada) y los textos.
class EstimatesReportTest < ActionDispatch::IntegrationTest
  setup do
    @round  = BusinessRound.create!(erp_round_id: 9705, name: "Rueda Rep", active: true)
    @cap    = User.create!(erp_person_id: 9705, username: "cap_rep", password: "secret123",
                           role: "capturista", active: true)
    @other  = User.create!(erp_person_id: 9706, username: "cap_rep2", password: "secret123",
                           role: "capturista", active: true)
    User.create!(erp_person_id: 9707, username: "srv_rep", password: "secret123", role: "server", active: true)
    @client = Client.create!(erp_client_key: "REP01", name: "ABARROTES LUNA",
                             salesperson: Salesperson.create!(erp_salesperson_id: 9705, name: "OMAR"))
    Setting.instance.update!(selected_round_erp_id: 9705, selected_round_name: "Rueda Rep")
  end

  def estimate!(user: @cap, client: nil, status: "draft", items: 1)
    @seq = (@seq || 0) + 1
    o = Order.create!(user: user, business_round: @round, document: "estimate", client: client,
                      kind: (client ? "remission" : nil), status: status,
                      local_folio: (status == "draft" ? nil : format("COT-%06d", @seq)))
    items.times { |i| o.order_items.create!(position: i + 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0) }
    o
  end

  def sale!
    Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission",
                  status: "captured", local_folio: "RN-009705")
  end

  test "el hub ofrece el reporte de cotizaciones" do
    login_as "cap_rep"
    get reports_path

    assert_select "a[href=?]", estimates_report_path, text: /Cotizaciones.*capturadas/m
  end

  test "lista solo cotizaciones, con el cliente genérico dicho" do
    generic = estimate!
    with_client = estimate!(client: @client, status: "captured")
    sale!
    login_as "cap_rep"

    get estimates_report_path

    assert_response :success
    assert_select "title", /Cotizaciones capturadas/
    assert_select "h1", "Cotizaciones capturadas"
    assert_match(/Mis cotizaciones/, response.body)
    assert_select "tbody tr", 2
    assert_no_match(/RN-009705/, response.body)
    assert_select "a[href=?][title='Abrir cotización']", order_path(generic), text: "(borrador)"
    assert_select "a[href=?]", order_path(with_client), text: "COT-000002"
    assert_match(/Cliente genérico/, response.body)
    assert_match(/REP01/, response.body)
    assert_select "form[action=?]", estimates_report_path
    assert_select "a[href=?]", reports_path, text: "← Volver a reportes"
  end

  test "el resumen tiene Borrador y Guardada, sin Transmitido" do
    estimate!
    estimate!(status: "captured", items: 2)
    login_as "cap_rep"

    get estimates_report_path

    assert_select "span", text: "Borrador"
    assert_select "span", text: "Guardada"
    assert_select "span", text: "Capturado", count: 0
    assert_select "span", text: "Transmitido", count: 0
    assert_select "a[href=?]", estimates_report_path(status: "captured", per_page: 25)
    assert_match(/\$232\.00/, response.body, "la guardada suma sus dos partidas")
  end

  test "se puede filtrar por cliente genérico y por un cliente" do
    estimate!
    estimate!(client: @client)
    login_as "cap_rep"

    # Sobre las celdas, no sobre la página: el combo de cliente lista a todos
    # los clientes y al genérico siempre.
    cells = -> { css_select("tbody tr td:nth-child(3)").map { |td| td.text.squish } }

    get estimates_report_path(client_id: "generic")
    assert_equal [ "Cliente genérico" ], cells.call

    get estimates_report_path(client_id: @client.id)
    assert_equal [ "REP01 — ABARROTES LUNA" ], cells.call
  end

  # Un orden por `clients.name` dejaba a la genérica en NULL y clavada al
  # final en las dos direcciones (la trampa de "(borrador)" en Clave local).
  test "ordenar por cliente mueve a la genérica como lo que muestra la celda" do
    estimate!(client: @client)        # ABARROTES LUNA
    estimate!                         # Cliente genérico
    login_as "cap_rep"

    get estimates_report_path(sort: "client", dir: "asc")
    rows = css_select("tbody tr td:nth-child(3)").map { |td| td.text.squish }
    assert_equal [ "REP01 — ABARROTES LUNA", "Cliente genérico" ], rows

    get estimates_report_path(sort: "client", dir: "desc")
    rows = css_select("tbody tr td:nth-child(3)").map { |td| td.text.squish }
    assert_equal [ "Cliente genérico", "REP01 — ABARROTES LUNA" ], rows
  end

  test "los estados vacíos hablan de cotizaciones" do
    login_as "cap_rep"

    get estimates_report_path
    assert_match(/Todavía no hay cotizaciones\./, response.body)

    estimate!
    get estimates_report_path(client_id: @client.id)
    assert_match(/Ninguna cotización coincide con lo que elegiste\./, response.body)
    assert_select "a[href=?]", estimates_report_path(per_page: 25), text: "Quitar filtros"
  end

  test "el servidor ve las de todos, solo para consultar" do
    estimate!(user: @cap)
    estimate!(user: @other)
    login_as "srv_rep"

    get estimates_report_path

    assert_select "tbody tr", 2
    assert_match(/Todas las cotizaciones/, response.body)
  end

  test "desde una cotización abierta del reporte se vuelve al reporte con sus filtros" do
    estimate = estimate!
    login_as "cap_rep"

    get order_path(estimate), headers: { "Referer" => "http://www.example.com#{estimates_report_path(status: 'draft', per_page: 50)}" }

    assert_select "a[href=?]", estimates_report_path(status: "draft", per_page: 50), text: "← Volver al reporte"
  end

  test "una página fuera de rango regresa al reporte de cotizaciones" do
    estimate!
    login_as "cap_rep"

    get estimates_report_path(page: 99)

    assert_redirected_to estimates_report_path(per_page: 25)
  end

  test "el reporte de pedidos no cambia: sus enlaces siguen apuntando a pedidos" do
    sale!
    login_as "cap_rep"

    get captured_orders_report_path

    assert_select "form[action=?]", captured_orders_report_path
    assert_select "span", text: "Capturado"
    assert_match(/Mis pedidos/, response.body)
  end
end
