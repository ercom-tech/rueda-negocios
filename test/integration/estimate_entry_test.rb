require "test_helper"

# Entrada a "Generar cotización" (decisión del usuario 2026-10-27): la
# tarjeta del menú, la pantalla con el buscador de cliente y el botón de
# cliente genérico, y los dos caminos que crean la cotización.
class EstimateEntryTest < ActionDispatch::IntegrationTest
  setup do
    @round  = BusinessRound.create!(erp_round_id: 9701, name: "Rueda Cot", active: true)
    @user   = User.create!(erp_person_id: 9701, username: "cap_cot", password: "secret123",
                           role: "capturista", active: true)
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1,
                                supplier: Supplier.create!(erp_supplier_id: 9701, name: "PROV"))
    # Cliente "pelón": una remisión no exige nada más del encabezado.
    @client = Client.create!(erp_client_key: "COT01", name: "Cliente Cot")
    @client.receipt_profiles.create!(name: "REMISION")
    Setting.instance.update!(selected_round_erp_id: 9701, selected_round_name: "Rueda Cot")
    login_as "cap_cot"
  end

  test "la tarjeta del menú lleva a generar cotización y ya no dice Próximamente" do
    get root_path

    assert_select "a[href=?]", new_estimate_path, text: /Generar.*cotización/m
    assert_no_match(/Generar.*cotización.*Próximamente/m, response.body.scan(/Generar.*?<\/a>/m).first.to_s)
  end

  test "la pantalla de entrada ofrece buscar un cliente o cotizar al genérico" do
    get new_estimate_path

    assert_response :success
    assert_select "h1", "Levantamiento de cotización"
    assert_select "input[name=client_key][placeholder=?]", "Buscar cliente por clave o nombre"
    assert_select "form[action=?] input[name=document][value=estimate]", new_order_path, visible: :all
    assert_select "form[action=?] button", orders_path, text: "Cliente genérico"
    assert_select "form[action=?] input[name='order[document]'][value=estimate]", orders_path, visible: :all
    assert_select "a[href=?]", root_path, text: "← Volver al menú"
  end

  test "cliente genérico crea la cotización sin encabezado y pasa a la captura" do
    assert_difference("Order.estimate.count", 1) do
      post orders_path, params: { order: { document: "estimate" } }
    end

    estimate = Order.estimate.last
    assert_redirected_to order_path(estimate)
    assert estimate.generic?
    assert estimate.draft?
    assert_equal @user, estimate.user
    assert_equal @round, estimate.business_round
  end

  test "las sugerencias del buscador conservan que se está cotizando" do
    get client_options_orders_path(q: "COT01", document: "estimate")

    assert_select "a[href=?]", new_order_path(client_key: "COT01", document: "estimate")
  end

  test "con cliente, el paso 1 es el del pedido y el encabezado se guarda como cotización" do
    get new_order_path(client_key: "COT01", document: "estimate")

    assert_response :success
    assert_select "h1", "Levantamiento de cotización"
    assert_select "input[name='order[document]'][value=estimate]", visible: :all
    assert_select "input[type=submit][value=?]", "Continuar a levantamiento de cotización"
    # Elegido un cliente, todavía puede cotizar al genérico (15ª auditoría).
    assert_select "form[action=?] button", orders_path, text: "Cliente genérico"

    assert_difference("Order.estimate.count", 1) do
      post orders_path, params: { order: { document: "estimate", client_id: @client.id, kind: "remission",
                                           client_receipt_profile_id: @client.receipt_profiles.first.id } }
    end
    estimate = Order.estimate.last
    assert_redirected_to order_path(estimate)
    assert_equal @client, estimate.client
    assert_not estimate.generic?
  end

  test "sin pedir cotización, el paso 1 sigue creando pedidos" do
    get new_order_path(client_key: "COT01")

    assert_select "h1", "Levantamiento de pedido"
    assert_select "input[name='order[document]']", count: 0, visible: :all
    assert_select "button", text: "Cliente genérico", count: 0

    post orders_path, params: { order: { client_id: @client.id, kind: "remission",
                                         client_receipt_profile_id: @client.receipt_profiles.first.id } }
    assert Order.last.sale?
  end

  # Un pedido no se puede crear sin cliente ni con el tipo forjado a otra cosa.
  test "un pedido sin cliente no se crea" do
    assert_no_difference("Order.count") do
      post orders_path, params: { order: { kind: "remission" } }
    end
    assert_response :unprocessable_entity
  end

  # El equipo-servidor solo consulta: su menú no tiene las tarjetas, y
  # tecleando la URL tampoco crea (15ª auditoría).
  test "el servidor no crea cotizaciones ni pedidos tecleando la URL" do
    User.create!(erp_person_id: 9799, username: "srv_cot", password: "secret123", role: "server", active: true)
    login_as "srv_cot"

    get new_estimate_path
    assert_redirected_to root_path
    assert_match(/es de los capturistas/, flash[:alert])

    get new_order_path(client_key: "COT01")
    assert_redirected_to root_path

    assert_no_difference("Order.count") do
      post orders_path, params: { order: { document: "estimate" } }
      post orders_path, params: { order: { client_id: @client.id, kind: "remission",
                                           client_receipt_profile_id: @client.receipt_profiles.first.id } }
    end
  end
end
