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

  test "dos toques no crean dos pedidos" do
    estimate = estimate!(client: @client)

    post convert_order_path(estimate)
    assert_no_difference -> { Order.count } do
      post convert_order_path(estimate)
    end

    assert_redirected_to root_path
    assert_equal ApplicationController::ORDER_GONE_MESSAGE, flash[:alert]
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
    assert_select "form[action=?][method=post]", convert_order_path(estimate)
    assert_select "input[type=submit][value=?]", "Convertir en pedido"

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
