require "test_helper"

# La cotización (`Order.estimate`): mismo registro que el pedido, con sus
# reglas propias — cliente opcional (genérico), folio COT- con consecutivo
# aparte, tipo fijo, y la purga que la borra al obtener información o cerrar
# la rueda.
class EstimateTest < ActiveSupport::TestCase
  setup do
    @user   = User.create!(erp_person_id: 9601, username: "cap_est", password: "x", role: "capturista")
    @round  = BusinessRound.create!(erp_round_id: 9601, name: "Rueda Est", active: true)
    @client = Client.create!(erp_client_key: "EST01", name: "Cliente Est")
  end

  def estimate(client: nil, **attrs)
    Order.new(user: @user, business_round: @round, document: "estimate", client: client, **attrs)
  end

  def with_item(order)
    order.order_items.build(quantity: 1, unit_price: 10, discount_percent: 0, tax_rate: 0)
    order
  end

  # --- Cliente ---------------------------------------------------------------

  test "la cotización de cliente genérico no exige cliente ni tipo" do
    order = estimate
    assert order.valid?, order.errors.full_messages.join(", ")
    assert order.generic?
    assert_nil order.kind
  end

  test "la cotización con cliente exige tipo y encabezado, como el pedido" do
    tax = @client.tax_profiles.create!(rfc: "XAXX010101000", business_name: "RAZON")
    order = estimate(client: @client, kind: "invoice")

    assert_not order.valid?
    assert order.errors[:client_tax_profile_id].any?, "una factura sin perfil fiscal no pasa"

    order.client_tax_profile = tax
    order.cfdi_use = CfdiUse.create!(code: "G01", description: "Adquisición")
    assert order.valid?, order.errors.full_messages.join(", ")
    assert_not order.generic?
  end

  test "un pedido sin cliente no es válido" do
    order = Order.new(user: @user, business_round: @round, kind: "remission")
    assert_not order.valid?
    assert order.errors[:client].any?
  end

  # La base lo impide aunque algo se salte la validación: un pedido sin
  # cliente se transmitiría al ERP sin a quién venderle.
  test "la base rechaza un pedido sin cliente aunque se salte la validación" do
    order = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    assert_raises(ActiveRecord::StatementInvalid) { order.update_columns(client_id: nil) }
  end

  test "al pasar a genérica se limpia el encabezado del cliente anterior" do
    branch = @client.branches.create!(name: "MATRIZ", is_default: true)
    order  = estimate(client: @client, kind: "remission", client_branch: branch)
    order.save!

    order.update!(client: nil)

    assert order.generic?
    assert_nil order.kind
    assert_nil order.client_branch_id
  end

  # --- Tipo fijo -------------------------------------------------------------

  test "el tipo se fija al crear: una cotización no se vuelve pedido ni al revés" do
    order = estimate(client: @client, kind: "remission")
    order.save!

    assert_not order.update(document: "sale")
    assert order.errors[:document].any?

    sale = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    assert_not sale.update(document: "estimate")
  end

  # --- Folio -----------------------------------------------------------------

  test "el folio es COT- con su propio consecutivo, aparte del de pedidos" do
    sale = with_item(Order.new(user: @user, business_round: @round, client: @client, kind: "remission"))
    sale.save!
    sale.capture!

    first  = with_item(estimate).tap(&:save!)
    second = with_item(estimate).tap(&:save!)
    first.capture!
    second.capture!

    assert_equal "COT-000001", first.local_folio
    assert_equal "COT-000002", second.local_folio
    assert_match(/\ARN-\d{6}\z/, sale.local_folio)
  end

  test "con prefijo de rueda, el folio es PREFIJO-COT-000001" do
    @round.update!(folio_prefix: "OAX")
    order = with_item(estimate).tap(&:save!)
    order.capture!

    assert_equal "OAX-COT-000001", order.local_folio
  end

  test "el consecutivo no retrocede cuando se borran cotizaciones" do
    first = with_item(estimate).tap(&:save!)
    first.capture!
    first.discard!

    second = with_item(estimate).tap(&:save!)
    second.capture!

    assert_equal "COT-000002", second.local_folio
  end

  test "volver a guardar conserva el folio" do
    order = with_item(estimate).tap(&:save!)
    order.capture!
    order.capture!

    assert_equal "COT-000001", order.local_folio
    assert_equal 1, Setting.instance.last_estimate_number
  end

  # --- Purga -----------------------------------------------------------------

  test "purge_estimates! borra las cotizaciones con sus partidas y respeta los pedidos" do
    sale = with_item(Order.new(user: @user, business_round: @round, client: @client, kind: "remission"))
    sale.save!
    with_item(estimate).tap(&:save!)
    with_item(estimate(client: @client, kind: "remission")).tap(&:save!)

    assert_equal 2, Order.purge_estimates!

    assert_equal [ sale.id ], Order.pluck(:id)
    assert_equal 1, OrderItem.count
  end

  # --- 15ª auditoría: huecos de cobertura -------------------------------------

  test "una cotización transmitida (no existe por flujo) no se va con la purga de transmitidos" do
    stray = with_item(estimate).tap(&:save!)
    stray.update_columns(status: "transmitted")

    Order.purge_transmitted!

    assert Order.exists?(stray.id)
  end

  test "si guardar falla, el número de cotización no se consume" do
    Setting.instance.update!(last_estimate_number: 4)
    # Con cliente y sin tipo: la validación de `kind` hace fallar el update!.
    order = with_item(estimate(client: @client)).tap { |o| o.save!(validate: false) }

    assert_raises(ActiveRecord::RecordInvalid) { order.capture! }

    assert_equal 4, Setting.instance.reload.last_estimate_number
    assert_nil order.reload.local_folio
  end

  test "badge y tarjetas leen el rótulo de la misma tabla" do
    saved = estimate.tap { |o| o.status = "captured" }

    assert_equal Order.status_labels_for("estimate")["captured"], saved.status_label
    assert_equal "Guardada", saved.status_label
    assert_equal "Capturado", Order.new(status: "captured").status_label
  end

  test "un client_id que no existe no es una cotización válida" do
    order = estimate(client_id: 999_999_999)

    assert_not order.valid?
    assert order.errors.of_kind?(:client, :blank)
  end

  # Los textos que salen del modelo y del servicio también nombran al
  # documento (16ª): DOCUMENT_TEXTS había llegado a vistas y controladores.
  test "los avisos del candado de promoción y del modal nombran a la cotización" do
    order = with_item(estimate).tap(&:save!)
    item = order.order_items.first
    promo = Promotion.create!(erp_promotion_id: 9601, code: "P", name: "P", starts_on: Date.current, ends_on: Date.current)
    item.update_columns(promotion_id: promo.id)

    assert_not item.reload.destroy
    assert_match(/Quita la promoción para quitarla de la cotización\./, item.errors.full_messages.first)
    assert_equal "Esta cotización no tiene productos de esta promoción.",
                 Promotions::Group.new(Order.find(order.id).tap { |o| o.order_items.delete_all }, promo).blocked_reason
  end
end
