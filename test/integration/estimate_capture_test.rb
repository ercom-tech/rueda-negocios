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
    # Con confirmación (15ª auditoría): el botón abre un modal, y es el modal
    # el que manda el cambio.
    assert_select "button[data-action='modal#open']", text: /Cliente genérico/
    assert_select "form[action=?] button", order_path(estimate), text: "Sí, cambiar"
    assert_select "form[action=?] input[name='order[client_id]'][value='']", order_path(estimate), visible: :all
    assert_select "form[action=?] button", order_path(estimate), text: "Cliente genérico", count: 0

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

  # La purga y una edición de partida pueden interbloquearse, y Postgres puede
  # abortar a la EDICIÓN: la cotización se borra igual, y el capturista veía
  # la pantalla de error en vez del aviso (17ª auditoría).
  test "si la edición pierde el interbloqueo con la purga, la pantalla dice que la cotización ya no está" do
    id = estimate!.id
    armed = true
    OrderItemsController.prepend(Module.new do
      define_method(:create) do
        return super() unless armed

        Order.purge_estimates!
        raise ActiveRecord::Deadlocked, "deadlock detected"
      end
    end)

    post order_order_items_path(id), params: { product_id: 1 }

    assert_redirected_to root_path
    assert_match(/ya no está en esta laptop/, flash[:alert])
  ensure
    armed = false # el módulo antepuesto se queda: se desarma (16ª)
  end

  # El buscador de cliente del paso 1 (al editar) pide con fetch. Sobre una
  # cotización ya borrada armaba las sugerencias como si no hubiera registro:
  # apuntaban a /orders/new, el paso 1 de un PEDIDO, y al guardar nacía una
  # venta en borrador sin que nada lo dijera (15ª auditoría).
  test "el buscador de cliente de una cotización borrada avisa en su panel y no ofrece crear un pedido" do
    estimate = estimate!(client: @client)
    id = estimate.id
    Order.where(id: id).then { |o| OrderItem.where(order_id: id).delete_all; o.delete_all }

    get client_options_orders_path(order_id: id, q: "CAP01")

    assert_response :success
    assert_select "[role=alert]", /ya no está en esta laptop/
    assert_select "a[href^='/orders/new']", count: 0
  end

  # El aviso del Cotizador cuando el registro entero ya no existe: puede ser
  # una cotización, y la causa puede ser el panel, no solo un descarte.
  test "el Cotizador sobre una cotización borrada no la llama pedido" do
    estimate = estimate!
    item = item!(estimate)
    Order.purge_estimates!

    get quote_order_order_item_path(estimate.id, item.id)

    assert_response :not_found
    assert_match(/ya no está en esta laptop/, response.body)
    assert_no_match(/Este pedido ya no existe/, response.body)
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

  # --- 15ª auditoría, BAJA ----------------------------------------------------

  test "la captura de una cotización no dice pedido" do
    estimate = estimate!
    item = item!(estimate)

    get order_path(estimate)

    assert_select "template[data-quote-template=empty]", text: /Esta cotización todavía no tiene productos/
    assert_match(/¿Quitar la partida 1, &quot;MARTILLO&quot;, de la cotización\?/, response.body)
    assert_no_match(/del pedido|este pedido|al pedido/i, response.body.gsub(/<!--.*?-->/m, ""))

    product = Product.create!(erp_product_id: 970_702, description: "MARTILLO", unit: "PZA")
    Price.create!(product: product, credit_wholesale_price: 100, tax_rate: 16)
    ProductSupplier.create!(product: product, supplier: Supplier.find_by!(erp_supplier_id: 9702))
    item.update_columns(product_id: product.id)
    get product_options_order_path(estimate, q: "MARTILLO")
    assert_match(/Ya está en la cotización, partida 1/, response.body)
  end

  test "el Cotizador sobre una partida quitada nombra a la cotización" do
    estimate = estimate!

    get quote_order_order_item_path(estimate, 999_999_999)

    assert_response :not_found
    assert_match(/Esa partida ya no está en la cotización/, response.body)
  end

  test "editar una genérica no dice 'para comenzar'" do
    get edit_order_path(estimate!)

    assert_match(/Busca al cliente si quieres asignarle esta cotización/, response.body)
    assert_no_match(/para comenzar/, response.body)
  end

  # Una partida quitada en otra pestaña: corregir su cantidad o tocar su bote
  # pintaba el 404 de Rails en lugar de la captura.
  test "corregir o quitar una partida que ya no está repinta la tabla con el aviso" do
    estimate = estimate!
    item = item!(estimate)
    item.delete

    patch order_order_item_path(estimate, item), params: { order_item: { quantity: 2 } }, as: :turbo_stream
    assert_response :success
    assert_match(/Esa partida ya no está en la cotización: se quitó desde otra pantalla/, response.body)
    assert_match(/<turbo-stream[^>]*target="order-detail"/, response.body)

    delete order_order_item_path(estimate, item), as: :turbo_stream
    assert_response :success
    assert_match(/Esa partida ya no está en la cotización/, response.body)
  end

  # La partida que entra justo cuando "Cerrar rueda" borra la cotización: la
  # llave foránea la rechaza. Se reproduce borrando la cotización entre la
  # lectura del controlador y el INSERT.
  test "una partida que llega a una cotización recién borrada lleva al menú con el aviso" do
    estimate = estimate!
    product = Product.create!(erp_product_id: 970_703, description: "PINZA", unit: "PZA")
    Price.create!(product: product, credit_wholesale_price: 100, tax_rate: 16)
    ProductSupplier.create!(product: product, supplier: Supplier.find_by!(erp_supplier_id: 9702))
    # Antepuesto y desarmado tras la primera llamada (ver close_round_test).
    fired = false
    Order.prepend(Module.new do
      define_method(:next_item_position) do
        unless fired
          fired = true
          Order.where(id: id).delete_all
        end
        super()
      end
    end)

    post order_order_items_path(estimate), params: { product_id: product.id }, as: :turbo_stream

    assert_redirected_to root_path
    assert_match(/ya no está en esta laptop/, flash[:alert])
  ensure
    fired = true # desarma el stub aunque la prueba no haya llegado a él (16ª)
  end

  test "el servidor no resuelve cotizaciones, y si lo fuerza el aviso dice por qué" do
    estimate = estimate!
    item!(estimate)
    login_as "srv_est"

    post capture_order_path(estimate)
    assert_match(/el equipo del servidor solo las consulta/, flash[:alert])
    delete order_path(estimate)
    assert_match(/el equipo del servidor solo las consulta/, flash[:alert])

    assert estimate.reload.draft?
    assert_equal 1, estimate.order_items.count
  end

  test "un cliente que no existe en una cotización es 'revisa los datos', no una pantalla de error" do
    assert_no_difference("Order.count") do
      post orders_path, params: { order: { document: "estimate", client_id: 999_999_999, kind: "remission" } }
    end
    assert_response :unprocessable_entity

    estimate = estimate!
    patch order_path(estimate), params: { order: { client_id: 999_999_999, kind: "remission" } }
    assert_response :unprocessable_entity
    assert estimate.reload.generic?
  end

  test "promoción ya quitada: el aviso nombra a la cotización" do
    estimate = estimate!
    promo = Promotion.create!(erp_promotion_id: 970_704, code: "P15", name: "P15",
                              starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)

    delete order_promotion_path(estimate, promo), as: :turbo_stream

    assert_match(/ya no estaba aplicada en esta cotización/, response.body)
  end

  # --- 16ª auditoría ------------------------------------------------------------

  # `order_gone` preguntaba `Order.exists?(id)` con el parámetro crudo: un
  # `?order_id[]=<condición>` llega como arreglo y Rails lo toma como
  # fragmento SQL. Con la respuesta distinta para verdadero (404) y falso
  # (302), un capturista tenía un oráculo para leer cualquier tabla — la
  # contraseña cifrada del operador incluida. Se afirma que la condición NO
  # llega a la base, no solo la respuesta: así no depende de qué haya en ella.
  test "un id forjado como arreglo no llega a la base como SQL" do
    estimate!
    marker = "audit16_probe"
    leaked = []
    callback = ->(*, payload) { leaked << payload[:sql] if payload[:sql].include?(marker) }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      # Lo que no existe cae en `order_gone`, que lee `order_id` antes que
      # `id`: un `order_id` de la query sobre una ruta que solo trae `id`.
      condition = "'#{marker}' = '#{marker}'"
      get order_path(999_999_999), params: { order_id: [ condition ] }
      get edit_order_path(999_999_999), params: { order_id: { "x" => condition } }
      get summary_order_path(999_999_999), params: { order_id: [ condition ] }
    end

    assert_empty leaked, "el parámetro forjado llegó como SQL:\n#{leaked.join("\n")}"
  end
end
