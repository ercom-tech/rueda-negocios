require "test_helper"

# El equipo-servidor resuelve un borrador AJENO: lo guarda o lo descarta.
#
# Existe porque un borrador abandonado —el capturista se fue, la tablet murió—
# bloquea las TRES operaciones del panel (obtener información, transmitir y
# cerrar rueda) y dejaba a la laptop sin salida en pleno evento: el único que
# podía resolverlo era su dueño, que ya no está.
class ServerResolvesDraftTest < ActionDispatch::IntegrationTest
  setup do
    @server = User.create!(erp_person_id: 969_001, username: "srv_draft", password: "secret123",
                           role: "server", active: true)
    @cap    = User.create!(erp_person_id: 969_002, username: "cap_draft", password: "secret123",
                           role: "capturista", active: true, name: "JUAN", paternal_surname: "PEREZ")
    @otro   = User.create!(erp_person_id: 969_003, username: "cap_otro", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 969_001, name: "Rueda 969", active: true)
    Setting.instance.update!(selected_round_erp_id: 969_001, selected_round_name: "Rueda 969")
    @sup    = Supplier.create!(erp_supplier_id: 969_001, name: "PROVEEDOR")
    BusinessRoundPerson.create!(business_round: @round, user: @cap, supplier: @sup, position: 1)
    @client = Client.create!(erp_client_key: "SRV01", name: "Cliente")
    @product = Product.create!(erp_product_id: 969_101, description: "MARTILLO", max_discount: 50)
    Price.create!(product: @product, credit_wholesale_price: 100, tax_rate: 16)
    ProductSupplier.create!(product: @product, supplier: @sup)
  end

  def draft_with_items!(owner: @cap)
    order = Order.create!(user: owner, business_round: @round, client: @client, kind: "remission")
    order.order_items.create!(product: @product, position: 1, quantity: 2, unit_price: 100,
                              discount_percent: 0, tax_rate: 16, code: @product.erp_code,
                              description: "MARTILLO", unit: "PZA")
    order
  end

  def empty_draft!(owner: @cap)
    Order.create!(user: owner, business_round: @round, client: @client, kind: "remission")
  end

  # El logger de Rails 8 es un BroadcastLogger y no admite `stub`: se le engancha
  # un destino extra y se lee lo que escribió.
  def capturando_el_log
    buffer = StringIO.new
    extra  = ActiveSupport::Logger.new(buffer)
    Rails.logger.broadcast_to(extra)
    yield
    buffer.string
  ensure
    Rails.logger.stop_broadcasting_to(extra)
  end

  # --- Lo que ve ---------------------------------------------------------

  test "el servidor ve Guardar y Descartar en un borrador ajeno" do
    order = draft_with_items!
    login_as "srv_draft"

    get order_path(order)

    assert_response :success
    assert_match(/Descartar/, response.body)
    assert_match(/Guardar/, response.body)
    assert_no_match(/Editar/, response.body, "resolver no es editar: el servidor no toca partidas ni encabezado")
  end

  # El modal nombra al capturista: el servidor resuelve pedidos que no capturó,
  # y "este pedido" no alcanza para decidir cuál está descartando.
  test "el modal de descarte dice de quién es el pedido" do
    order = draft_with_items!
    login_as "srv_draft"

    get order_path(order)

    assert_match(/JUAN PEREZ/, response.body)
  end

  test "en un pedido ajeno YA CAPTURADO no ofrece resolverlo" do
    order = draft_with_items!
    order.capture!
    login_as "srv_draft"

    get order_path(order)

    assert_response :success
    assert_no_match(/Sí, descartar/, response.body,
                    "un capturado ya tiene folio y es transmisible: borrarlo es otra decisión")
  end

  # --- Lo que puede hacer -------------------------------------------------

  test "el servidor descarta un borrador ajeno" do
    order = draft_with_items!
    login_as "srv_draft"

    delete order_path(order)

    assert_redirected_to root_path
    assert_nil Order.find_by(id: order.id)
    assert_empty OrderItem.where(order_id: order.id), "las partidas se van con el pedido"
  end

  test "el servidor guarda un borrador ajeno, y sigue siendo del capturista" do
    order = draft_with_items!
    login_as "srv_draft"

    post capture_order_path(order)

    order.reload
    assert order.captured?
    assert_match(/\ARN-\d{6}\z/, order.local_folio)
    assert_equal @cap.id, order.user_id, "resolver no es apropiarse: el pedido sigue siendo de quien lo capturó"
  end

  # El servidor NO puede agregar productos a un pedido ajeno, así que mandarlo
  # a hacerlo es un callejón sin salida: su salida es descartarlo.
  test "un borrador vacío le dice al servidor que lo descarte, no que agregue productos" do
    order = empty_draft!
    login_as "srv_draft"

    post capture_order_path(order)

    assert_redirected_to order_path(order)
    assert_match(/[Dd]escárta/, flash[:alert])
    assert_no_match(/Agrega al menos un producto/, flash[:alert])
    assert order.reload.draft?
  end

  test "al capturista dueño le sigue diciendo que agregue un producto" do
    order = empty_draft!
    login_as "cap_draft"

    post capture_order_path(order)

    assert_match(/Agrega al menos un producto/, flash[:alert])
  end

  # El rastro tiene que decir CUÁL borrador: el capturista no se entera de que
  # le resolvieron el suyo, y en la revisión posterior "¿quién borró esto?" no
  # tiene otra respuesta. Un borrador no tiene folio —`folio` devuelve el texto
  # "(borrador)"—, así que ahí va el id.
  test "el log identifica el borrador descartado, que no tiene folio" do
    order = draft_with_items!
    login_as "srv_draft"

    salida = capturando_el_log { delete order_path(order) }

    assert_match(/srv_draft \(server\) descartado/, salida)
    assert_match(/id #{order.id}/, salida)
    assert_match(/de cap_draft/, salida)
    assert_no_match(/\(borrador\)/, salida, "eso no identifica cuál de los borradores era")
  end

  test "al guardarlo, el log lo nombra por su folio recién asignado" do
    order = draft_with_items!
    login_as "srv_draft"

    salida = capturando_el_log { post capture_order_path(order) }

    assert_match(/guardado el borrador #{order.reload.local_folio}/, salida)
  end

  # --- Lo que NO puede hacer ---------------------------------------------

  test "el servidor no puede descartar un pedido ajeno ya capturado" do
    order = draft_with_items!
    order.capture!
    login_as "srv_draft"

    # 404 y no un mensaje: a este endpoint no se llega desde la pantalla, solo
    # a mano. Es la misma respuesta que daba `current_user.orders.find`.
    delete order_path(order)

    assert_response :not_found
    assert Order.exists?(order.id)
  end

  test "un capturista no puede tocar el borrador de otro capturista" do
    order = draft_with_items!
    login_as "cap_otro"

    delete order_path(order)
    assert_response :not_found

    post capture_order_path(order)
    assert_response :not_found

    assert Order.exists?(order.id)
    assert order.reload.draft?
  end
end
