require "test_helper"

# La captura de una cotización es la misma pantalla del pedido (decisión del
# usuario 2026-10-27): cambian los textos, el encabezado del cliente genérico,
# el paso 3 sin PDF ni correo, y el aviso cuando la cotización ya no existe.
class EstimateCaptureTest < ActionDispatch::IntegrationTest
  setup do
    @round  = BusinessRound.create!(erp_round_id: 9702, name: "Rueda Cap", active: true)
    @user   = User.create!(erp_person_id: 9702, username: "cap_est", password: "secret123",
                           role: "capturista", active: true)
    @other  = User.create!(erp_person_id: 9703, username: "cap_otro", password: "secret123",
                           role: "capturista", active: true)
    User.create!(erp_person_id: 9704, username: "srv_est", password: "secret123", role: "server", active: true)
    supplier = Supplier.create!(erp_supplier_id: 9702, name: "PROV")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: supplier)
    @client = Client.create!(erp_client_key: "CAP01", name: "Cliente Cap")
    @client.receipt_profiles.create!(name: "REMISION")
    Setting.instance.update!(selected_round_erp_id: 9702, selected_round_name: "Rueda Cap")
    login_as "cap_est"
  end

  def estimate!(client: nil, status: "draft")
    Order.create!(user: @user, business_round: @round, document: "estimate", client: client,
                  kind: (client ? "remission" : nil), status: status,
                  client_receipt_profile: client&.receipt_profiles&.first)
  end

  def item!(order)
    order.order_items.create!(position: 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0,
                              code: "000001", description: "MARTILLO", unit: "PZA")
  end

  # --- La captura -----------------------------------------------------------

  test "la genérica se captura sin encabezado y dice que es cotización" do
    get order_path(estimate!)

    assert_response :success
    assert_select "title", /Levantamiento de cotización/
    assert_select "h1", "Levantamiento de cotización"
    assert_select "h2", /# Cotización \(borrador\)/
    assert_match(/Cliente genérico/, response.body)
    assert_no_match(/Clave del cliente/, response.body)
    assert_select "a", text: "Descargar PDF", count: 0
    assert_select "a", text: "Editar"
    assert_select "button", text: "Descartar"
    assert_select "button", text: "Guardar"
    assert_select "h3", text: "Descartar cotización"
    assert_select "[aria-label='Observaciones de la cotización']"
  end

  test "con cliente, el encabezado es el del pedido" do
    get order_path(estimate!(client: @client))

    assert_response :success
    assert_match(/Clave del cliente/, response.body)
    assert_match(/CAP01/, response.body)
    assert_select "a", text: "Descargar PDF", count: 0
  end

  test "descartar dice cotización" do
    estimate = estimate!

    delete order_path(estimate)

    assert_redirected_to root_path
    assert_equal "Cotización descartada.", flash[:notice]
    assert_not Order.exists?(estimate.id)
  end

  test "guardar asigna folio COT-, muestra Guardada y lleva al resumen sin PDF ni correo" do
    estimate = estimate!
    item!(estimate)

    post capture_order_path(estimate)
    assert_redirected_to summary_order_path(estimate)
    assert_equal "COT-000001", estimate.reload.local_folio

    follow_redirect!
    assert_select "h2", "Resumen de la cotización"
    assert_match(/Cotización <span class="font-bold">#COT-000001<\/span> guardada correctamente/, response.body)
    assert_no_match(/Descargar PDF|Enviar por correo/, response.body)
    assert_select "a[href=?]", new_estimate_path, text: "Capturar otra cotización"
    assert_select "a[href=?]", order_path(estimate), text: "← Volver a la cotización"

    get order_path(estimate)
    assert_select "span", text: "Guardada"
    assert_select "h2", /# Cotización COT-000001/
  end

  test "una cotización vacía no se guarda, y el aviso la llama cotización" do
    estimate = estimate!

    post capture_order_path(estimate)

    assert_redirected_to order_path(estimate)
    assert_equal "Agrega al menos un producto antes de guardar la cotización.", flash[:alert]
  end

  test "una cotización no tiene PDF" do
    estimate = estimate!(status: "captured")
    estimate.update_columns(local_folio: "COT-000009")

    get pdf_order_path(estimate)

    assert_response :not_found
  end

  # --- Editar el encabezado en los dos sentidos ------------------------------

  test "una cotización con cliente puede pasar a genérica" do
    estimate = estimate!(client: @client)

    get edit_order_path(estimate)
    assert_response :success
    assert_select "a[href=?]", order_path(estimate), text: "← Volver a la cotización"
    assert_select "form[action=?] button", order_path(estimate), text: "Cliente genérico"

    patch order_path(estimate), params: { order: { client_id: "" } }

    assert_redirected_to order_path(estimate)
    estimate.reload
    assert estimate.generic?
    assert_nil estimate.client_receipt_profile_id
    assert_nil estimate.kind
  end

  test "una genérica puede tomar un cliente" do
    estimate = estimate!

    get edit_order_path(estimate)
    assert_response :success
    assert_select "button", text: "Cliente genérico", count: 0, visible: :all

    get edit_order_path(estimate, client_key: "CAP01")
    assert_response :success
    assert_select "input[name='order[client_id]'][value=?]", @client.id.to_s, visible: :all
    # Todavía no hay cliente guardado: el botón de volverla genérica no aplica.
    assert_select "button", text: "Cliente genérico", count: 0, visible: :all

    patch order_path(estimate), params: { order: { client_id: @client.id, kind: "remission",
                                                   client_receipt_profile_id: @client.receipt_profiles.first.id } }
    assert_redirected_to order_path(estimate)
    assert_equal @client, estimate.reload.client
  end

  # --- Cuando la cotización ya no existe -------------------------------------
  # Obtener información y cerrar la rueda la borran aunque alguien la tenga
  # abierta: su siguiente toque tiene que decir qué pasó, no "No encontramos
  # esa pantalla".
  test "si la cotización se borró, la pantalla lo dice y regresa al menú" do
    estimate = estimate!
    id = estimate.id
    Order.purge_estimates!

    get order_path(id)
    assert_redirected_to root_path
    assert_match(/ya no está en esta laptop/, flash[:alert])

    post order_order_items_path(id), params: { product_id: 1 }
    assert_redirected_to root_path

    # El buscador de producto trae sus sugerencias con fetch: la respuesta va
    # dentro del panel, no como redirección (que el fetch seguiría y metería
    # el menú entero en el panel).
    get product_options_order_path(id, q: "MART")
    assert_response :success
    assert_select "[role=alert]", /ya no está en esta laptop/
    assert_select "[role=alert] a[href=?]", root_path
  end

  test "un pedido ajeno sigue siendo 404, no 'ya no está'" do
    other = Order.create!(user: @other, business_round: @round, client: @client, kind: "remission",
                          client_receipt_profile: @client.receipt_profiles.first)

    delete order_path(other)

    assert_response :not_found
  end

  # --- El equipo-servidor solo consulta ---------------------------------------

  test "el servidor ve la cotización sin botones de acción" do
    estimate = estimate!
    item!(estimate)
    login_as "srv_est"

    get order_path(estimate)

    assert_response :success
    assert_select "a", text: "Descargar PDF", count: 0
    assert_select "button", text: "Descartar", count: 0
    assert_select "button", text: "Guardar", count: 0
  end
end
