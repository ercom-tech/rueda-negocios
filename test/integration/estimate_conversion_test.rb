require "test_helper"

# "Convertir en pedido" (decisión del usuario 2026-11-04): una cotización
# GUARDADA se vuelve un pedido NUEVO —ya guardado, con el folio que sigue— y
# la cotización se borra. La de cliente genérico pasa antes por el paso 1 a
# elegir cliente; la que ya lo tiene se convierte directo.
class EstimateConversionTest < ActionDispatch::IntegrationTest
  setup do
    @round = BusinessRound.create!(erp_round_id: 9801, name: "Rueda Conv", active: true, folio_prefix: "CNV")
    @user  = User.create!(erp_person_id: 9801, username: "cap_conv", password: "secret123",
                          role: "capturista", active: true)
    @other = User.create!(erp_person_id: 9802, username: "cap_conv2", password: "secret123",
                          role: "capturista", active: true)
    User.create!(erp_person_id: 9803, username: "srv_conv", password: "secret123", role: "server", active: true)
    supplier = Supplier.create!(erp_supplier_id: 9801, name: "PROV CONV")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: supplier)
    Setting.instance.update!(selected_round_erp_id: 9801, selected_round_name: "Rueda Conv")

    @client = Client.create!(erp_client_key: "CNV01", name: "CLIENTE CONV")
    @receipt = @client.receipt_profiles.create!(name: "REMISION CONV")
    @branch  = @client.branches.create!(erp_branch_id: 1, name: "MATRIZ", is_default: true)

    @drill = Product.create!(erp_product_id: 980_101, description: "TALADRO CONV", unit: "PZA", max_discount: 50)
    @saw   = Product.create!(erp_product_id: 980_102, description: "SIERRA CONV", unit: "PZA", max_discount: 50)
    [ @drill, @saw ].each { |p| Price.create!(product: p, credit_wholesale_price: 1000, tax_rate: 16) }
    login_as "cap_conv"
  end

  def estimate!(client: nil, status: "captured", user: @user)
    estimate = Order.create!(user: user, business_round: @round, document: "estimate", client: client,
                             kind: (client ? "remission" : nil), status: "draft",
                             client_receipt_profile: (@receipt if client), client_branch: (@branch if client),
                             observations: "ENTREGAR EN BODEGA 3")
    [ @drill, @saw ].each_with_index do |product, i|
      estimate.order_items.create!(product.to_order_item_attributes.merge(position: i + 1, quantity: 2 + i,
                                                                         discount_percent: 5))
    end
    estimate.capture! if status == "captured"
    estimate.reload
  end

  # Las dos partidas en UNA promoción aplicada: la validación de alta de
  # OrderItem rechazaría la segunda si la copia fuera partida por partida.
  def promoted_estimate!(ends_on: 1.week.from_now.to_date)
    promo = Promotion.create!(erp_promotion_id: 980_101, code: "CNV", name: "MAKITA CONV",
                              starts_on: 1.week.ago.to_date, ends_on: ends_on)
    promo.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CM", unit: "MXN",
                                  quantity_from: 1, quantity_to: 0, discount_percent: 12)
    [ @drill, @saw ].each { |p| promo.promotion_products.create!(product: p, discount_percent: 0) }
    estimate = estimate!(client: @client, status: "draft")
    assert Promotions::Group.new(estimate, promo).apply!
    estimate.capture!
    estimate.reload
  end

  def item_snapshot(order)
    order.order_items.order(:position).map do |i|
      i.attributes.except("id", "order_id", "created_at", "updated_at")
    end
  end

  # --- Con cliente: directo -------------------------------------------------

  test "con cliente se convierte directo en un pedido guardado y la cotización se borra" do
    estimate = estimate!(client: @client)
    items    = item_snapshot(estimate)
    total    = estimate.total

    assert_difference -> { Order.sale.count } => 1, -> { Order.estimate.count } => -1 do
      post convert_order_path(estimate)
    end

    sale = Order.sale.last
    assert_redirected_to summary_order_path(sale)
    assert_equal "La cotización #{estimate.local_folio} se convirtió en el pedido #{sale.local_folio}.", flash[:notice]
    assert_predicate sale, :captured?
    assert_equal [ @client.id, "remission", @receipt.id, @branch.id, "ENTREGAR EN BODEGA 3", @user.id, @round.id ],
                 [ sale.client_id, sale.kind, sale.client_receipt_profile_id, sale.client_branch_id,
                   sale.observations, sale.user_id, sale.business_round_id ]
    assert_equal items, item_snapshot(sale), "las partidas pasan tal cual: precio, descuento, posición"
    assert_equal total, sale.total
    assert_not Order.exists?(estimate.id)
    assert_equal 0, OrderItem.where(order_id: estimate.id).count
  end

  # El folio del pedido sale del id: el de un registro NUEVO es el que sigue.
  # Volteando la cotización saldría su id viejo, debajo de pedidos posteriores.
  test "el pedido toma el folio que sigue disponible, no el de la cotización" do
    estimate = estimate!(client: @client)
    later = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission",
                          client_receipt_profile: @receipt, client_branch: @branch)

    post convert_order_path(estimate)

    sale = Order.sale.last
    assert_operator sale.id, :>, later.id
    assert_equal "CNV-#{sale.id.to_s.rjust(6, '0')}", sale.local_folio
    assert_match(/\ACNV-\d{6}\z/, sale.local_folio)
  end

  test "las partidas de una promoción aplicada se convierten con su promoción" do
    estimate = promoted_estimate!
    items    = item_snapshot(estimate)
    assert items.all? { |i| i["promotion_id"].present? }, "el caso necesita las dos partidas en la promoción"

    post convert_order_path(estimate)

    sale = Order.sale.last
    assert_redirected_to summary_order_path(sale)
    assert_equal items, item_snapshot(sale)
  end

  # Los dos tipos de partida que más columnas propias llevan: el regalo (al
  # 100%) y el fuera de catálogo 999999 con su proveedor y su No. de parte. La
  # copia es directa; que no se pierda ninguna columna (18ª, hueco de cobertura).
  test "un regalo y un fuera de catálogo pasan con todas sus columnas" do
    supplier = Supplier.find_by!(erp_supplier_id: 9801)
    generic  = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "PRODUCTO NUEVO", unit: "PZA")
    estimate = estimate!(client: @client, status: "draft")
    estimate.order_items.first.update_columns(gift: true, discount_percent: 100)
    estimate.order_items.new(product: generic, position: 3, quantity: 4, unit_price: 250, tax_rate: 16,
                             discount_percent: 0, code: "999999", description: "SOPLADORA X", unit: "PZA",
                             part_number: "SX-1", supplier_id: supplier.id).save!(validate: false)
    estimate.capture!
    items = item_snapshot(estimate.reload)
    total = estimate.total

    post convert_order_path(estimate)

    sale = Order.sale.last
    assert_equal items, item_snapshot(sale)
    assert_equal total, sale.total
    assert sale.order_items.find_by(code: "999999").then { |i| i.supplier_id == supplier.id && i.part_number == "SX-1" }
  end

  # La concordancia con número literal (convenciones: una regla con número
  # necesita una prueba que lo escriba).
  test "el modal concuerda con una y con varias partidas" do
    get order_path(estimate!(client: @client))
    assert_match(/con las 2 partidas de esta cotización/, response.body)

    single = estimate!(client: @client, status: "draft")
    single.order_items.last.delete
    single.capture!
    get order_path(single)
    assert_match(/con la partida de esta cotización/, response.body)
  end

  test "varias promociones vencidas se nombran juntas, en plural" do
    estimate = promoted_estimate!
    second = Promotion.create!(erp_promotion_id: 980_102, code: "CNV2", name: "DEWALT CONV",
                               starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    estimate.order_items.last.update_columns(promotion_id: second.id)
    Promotion.where(code: %w[CNV CNV2]).update_all(ends_on: 2.days.ago.to_date)

    post convert_order_path(estimate)

    assert_equal "Las promociones DEWALT CONV y MAKITA CONV ya no están vigentes. " \
                 "Quítalas de la cotización antes de convertirla en pedido.", flash[:alert]
  end

  # Inalcanzable en operación (el encabezado de la cotización pasó las mismas
  # validaciones); forzado, decía "Client branch es obligatoria", en inglés.
  test "un encabezado que ya no valida se dice sin nombres de campo" do
    estimate = estimate!(client: @client)
    estimate.update_columns(client_branch_id: nil)

    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate)
    end

    assert_redirected_to order_path(estimate)
    assert_equal "No se pudo convertir: al encabezado de la cotización le falta un dato. " \
                 "Ábrelo con Editar, complétalo y vuelve a convertirla.", flash[:alert]
  end

  test "una promoción vencida bloquea la conversión y dice cuál quitar" do
    estimate = promoted_estimate!
    Promotion.find_by(code: "CNV").update_columns(ends_on: 2.days.ago.to_date)

    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate)
    end

    assert_redirected_to order_path(estimate)
    assert_equal "La promoción MAKITA CONV ya no está vigente. Quítala de la cotización antes de convertirla en pedido.",
                 flash[:alert]
    assert Order.exists?(estimate.id)
  end

  # El segundo toque decía "se descartó, o se borró al obtener la información":
  # el capturista creía perdida una cotización que ya era pedido, y podía
  # capturarla otra vez — una venta duplicada al ERP (18ª auditoría).
  test "dos toques no crean dos pedidos, y el segundo dice que pudo convertirse" do
    estimate = estimate!(client: @client)

    post convert_order_path(estimate)
    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate)
    end

    assert_redirected_to root_path
    assert_equal OrdersController::ESTIMATE_GONE_MESSAGE, flash[:alert]
    assert_match(/se convirtió en pedido/, flash[:alert])
  end

  test "volver al paso 1 de una conversión ya hecha dice que pudo convertirse" do
    estimate = estimate!
    post convert_order_path(estimate), params: { order: { client_id: @client.id, kind: "remission",
                                                          client_receipt_profile_id: @receipt.id,
                                                          client_branch_id: @branch.id } }

    get conversion_order_path(estimate)

    assert_redirected_to root_path
    assert_equal OrdersController::ESTIMATE_GONE_MESSAGE, flash[:alert]
  end

  test "el aviso general de 'ya no está' también nombra la conversión" do
    assert_match(/se convirtió en pedido/, ApplicationController::ORDER_GONE_MESSAGE)
  end

  # --- La cotización cambió de forma entre la pantalla y el envío -----------
  # El controlador decidía con la forma de AHORA: el paso 1 de una genérica a
  # la que en otra pestaña le asignaron cliente convertía con ESE cliente e
  # ignoraba el elegido en pantalla; y el modal de una con cliente que se
  # volvió genérica daba 400 (`params.require`).

  test "si a la genérica le asignaron cliente en otra pestaña, no se convierte con otro" do
    estimate = estimate!
    other = Client.create!(erp_client_key: "CNV09", name: "OTRO CLIENTE")
    other_receipt = other.receipt_profiles.create!(name: "REMISION OTRO")
    other_branch  = other.branches.create!(erp_branch_id: 1, name: "MATRIZ", is_default: true)
    estimate.update!(client: @client, kind: "remission", client_receipt_profile: @receipt, client_branch: @branch)

    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate), params: { order: { client_id: other.id, kind: "remission",
                                                            client_receipt_profile_id: other_receipt.id,
                                                            client_branch_id: other_branch.id } }
    end

    assert_redirected_to order_path(estimate)
    assert_equal Order::CONVERSION_CHANGED_MESSAGE, flash[:alert]
  end

  test "si la que tenía cliente se volvió genérica, el modal no da error" do
    estimate = estimate!(client: @client)
    estimate.update!(client: nil)

    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate)
    end

    assert_redirected_to order_path(estimate)
    assert_equal Order::CONVERSION_CHANGED_MESSAGE, flash[:alert]
  end

  # --- Genérica: paso 1 -----------------------------------------------------

  test "la genérica no se convierte sin elegir cliente" do
    estimate = estimate!

    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate), params: { order: { client_id: "" } }
    end

    assert_response :unprocessable_entity
    assert Order.exists?(estimate.id)
  end

  test "la genérica pasa por el paso 1 y se convierte con el cliente elegido" do
    estimate = estimate!
    items    = item_snapshot(estimate)

    get conversion_order_path(estimate)
    assert_response :success
    assert_select "a[href=?]", order_path(estimate), text: "← Volver a la cotización"
    assert_match(/Las 2 partidas de la\s+cotización <span class="font-semibold">#{estimate.local_folio}/, response.body)

    get conversion_order_path(estimate, client_key: "CNV01")
    assert_select "form#conversion-form[action=?][method=post]", convert_order_path(estimate)
    assert_select "button[type=submit][form=conversion-form]", text: "Sí, convertir"

    post convert_order_path(estimate), params: { order: { client_id: @client.id, kind: "remission",
                                                          client_receipt_profile_id: @receipt.id,
                                                          client_branch_id: @branch.id } }

    sale = Order.sale.last
    assert_redirected_to summary_order_path(sale)
    assert_equal [ @client.id, "remission", @receipt.id ], [ sale.client_id, sale.kind, sale.client_receipt_profile_id ]
    assert_equal items, item_snapshot(sale)
    assert_not Order.exists?(estimate.id)
  end

  # Los perfiles viajan en campos ocultos: el combo no es una restricción.
  test "la genérica no se convierte con la remisión de otro cliente" do
    estimate = estimate!
    stranger = Client.create!(erp_client_key: "CNV02", name: "OTRO")
    foreign_receipt = stranger.receipt_profiles.create!(name: "AJENA")

    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate), params: { order: { client_id: @client.id, kind: "remission",
                                                            client_receipt_profile_id: foreign_receipt.id,
                                                            client_branch_id: @branch.id } }
    end
    assert_response :unprocessable_entity
  end

  test "las sugerencias de cliente siguen en la conversión" do
    estimate = estimate!

    get client_options_orders_path(q: "CNV01", conversion_id: estimate.id)

    assert_select "a[href=?]", conversion_order_path(estimate, client_key: "CNV01")
  end

  # --- Quién y cuándo ---------------------------------------------------------

  test "un borrador todavía no se convierte" do
    estimate = estimate!(client: @client, status: "draft")

    post convert_order_path(estimate)

    assert_response :not_found
    assert Order.exists?(estimate.id)
  end

  test "la cotización de otro capturista no se convierte" do
    estimate = estimate!(client: @client, user: @other)

    post convert_order_path(estimate)

    assert_response :not_found
    assert Order.exists?(estimate.id)
  end

  test "el equipo del servidor no convierte" do
    estimate = estimate!(client: @client)
    login_as "srv_conv"

    post convert_order_path(estimate)

    assert_redirected_to root_path
    assert Order.exists?(estimate.id)
  end

  test "mientras corre un sync no se convierte" do
    estimate = estimate!(client: @client)
    SyncRun.create!(kind: "down", status: "running", pid: Process.pid, started_at: Time.current)

    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate)
    end
    assert Order.exists?(estimate.id)
  end

  # --- Dónde está el botón -----------------------------------------------------

  test "el botón está en la cotización guardada y en su resumen, no en el borrador" do
    estimate = estimate!(client: @client)
    get order_path(estimate)
    assert_select "button", text: "Convertir en pedido"
    get summary_order_path(estimate)
    assert_select "button", text: /Convertir en pedido/

    generic = estimate!
    get order_path(generic)
    assert_select "a[href=?]", conversion_order_path(generic), text: "Convertir en pedido"

    get order_path(estimate!(client: @client, status: "draft"))
    assert_select "button", text: "Convertir en pedido", count: 0
  end

  test "el equipo del servidor no ve el botón" do
    estimate = estimate!(client: @client)
    login_as "srv_conv"

    get order_path(estimate)
    assert_select "button", text: /Convertir en pedido/, count: 0
    get summary_order_path(estimate)
    assert_select "button", text: /Convertir en pedido/, count: 0
  end
end
