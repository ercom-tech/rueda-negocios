require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    @user   = User.create!(erp_person_id: 9001, username: "cap_test", password: "x", role: "capturista")
    @round  = BusinessRound.create!(erp_round_id: 9001, name: "Rueda Test", active: true)
    # Cliente "pelón" (sin perfiles/sucursales) → una remisión no exige nada más.
    @client = Client.create!(erp_client_key: "TEST01", name: "Cliente Test")
  end

  def build_order
    Order.new(user: @user, business_round: @round, client: @client, kind: "remission")
  end

  test "totales agregados: descuento e IVA por partida" do
    order = build_order
    order.order_items.build(quantity: 2, unit_price: 100, discount_percent: 10, tax_rate: 16)
    order.order_items.build(quantity: 1, unit_price: 50,  discount_percent: 0,  tax_rate: 16)

    assert_equal 250, order.subtotal          # 200 + 50
    assert_equal 20,  order.discount_total     # 20 + 0
    assert_in_delta 36.8,  order.tax_total, 0.001   # 28.8 + 8
    assert_in_delta 266.8, order.total,     0.001   # 250 - 20 + 36.8
  end

  test "capture! marca el pedido como capturado y asigna folio local" do
    order = build_order
    order.order_items.build(quantity: 1, unit_price: 10, discount_percent: 0, tax_rate: 0)
    order.save!

    assert order.draft?
    assert order.capture!
    assert order.captured?
    assert_match(/\ARN-\d{6}\z/, order.local_folio)
  end

  test "capture! no procede sin partidas" do
    order = build_order
    order.save!

    assert_not order.capture!
    assert order.draft?
  end

  test "editable? salvo cuando está transmitido" do
    order = build_order
    assert order.editable?
    assert order.draft? && order.editable?

    order.status = "captured"
    assert order.editable?

    order.status = "transmitted"
    assert_not order.editable?
  end

  test "status_label en español para cada estado" do
    order = build_order
    assert_equal "Borrador", order.status_label
    order.status = "captured"
    assert_equal "Capturado", order.status_label
    order.status = "transmitted"
    assert_equal "Transmitido", order.status_label
  end
  test "las observaciones se normalizan a mayúsculas (van al ERP)" do
    order = build_order
    order.observations = "Entregar en bodega trasera, cañón #2"
    order.save!

    assert_equal "ENTREGAR EN BODEGA TRASERA, CAÑÓN #2", order.reload.observations
  end

  # --- Consecutivo de partidas -------------------------------------------

  def order_with_items(count)
    order = build_order
    order.save!
    count.times { |i| order.order_items.create!(position: i + 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0) }
    order
  end

  test "renumber_items! cierra el hueco al borrar una partida intermedia" do
    order = order_with_items(4)
    order.order_items.find_by(position: 2).destroy

    assert_equal [ 1, 3, 4 ], order.order_items.reload.map(&:position), "el hueco existe antes de renumerar"

    order.renumber_items!

    assert_equal [ 1, 2, 3 ], order.order_items.reload.map(&:position)
  end

  test "tras renumerar, la siguiente partida sigue el consecutivo sin saltos" do
    order = order_with_items(4)
    order.order_items.find_by(position: 2).destroy
    order.renumber_items!

    assert_equal 4, order.next_item_position
  end

  test "renumerar respeta el orden actual y es idempotente" do
    order = order_with_items(3)
    ids = order.order_items.reload.map(&:id)

    order.renumber_items!

    assert_equal ids, order.order_items.reload.map(&:id), "no debe reordenar las partidas"
    assert_equal [ 1, 2, 3 ], order.order_items.map(&:position)
  end

  # --- La rama inactiva del encabezado se descarta al guardar ---------------
  # El paso 1 pinta los campos de factura y los de remisión en el mismo
  # formulario y solo oculta con CSS los de la rama que no aplica, así que se
  # envían igual. Sin esto, un pedido que empezó como factura y terminó como
  # remisión viajaba al ERP con el RFC real del cliente.

  def profiles_client
    client = Client.create!(erp_client_key: "TEST02", name: "Cliente Con Perfiles")
    tax    = ClientTaxProfile.create!(client: client, rfc: "AAA010101AAA", business_name: "CLIENTE SA")
    receipt = ClientReceiptProfile.create!(client: client, erp_receipt_profile_id: 1, name: "MATRIZ")
    cfdi   = CfdiUse.create!(code: "G01", description: "ADQUISICIÓN DE MERCANCÍAS")
    [ client, tax, receipt, cfdi ]
  end

  test "una remisión no conserva el perfil fiscal ni el uso de CFDI" do
    client, tax, receipt, cfdi = profiles_client
    order = Order.new(user: @user, business_round: @round, client: client, kind: "remission",
                      client_tax_profile: tax, cfdi_use: cfdi, client_receipt_profile: receipt)

    assert order.save, order.errors.full_messages.to_sentence

    assert_nil order.client_tax_profile_id, "una remisión no lleva el RFC del cliente"
    assert_nil order.cfdi_use_id
    assert_equal receipt.id, order.client_receipt_profile_id
  end

  test "cambiar a remisión también suelta el monto de división de facturas" do
    client, tax, receipt, cfdi = profiles_client
    order = Order.create!(user: @user, business_round: @round, client: client, kind: "invoice",
                          client_tax_profile: tax, cfdi_use: cfdi,
                          dividir_facturas: DivideAmount.create!(erp_consecutive: 1, amount: 2000).amount)

    assert order.update(kind: "remission", client_receipt_profile: receipt)

    assert_equal 0, order.reload.dividir_facturas,
                 "el campo se oculta en remisión: si sobrevive, nadie puede corregirlo"
  end

  test "una factura no conserva el perfil de remisión" do
    client, tax, receipt, cfdi = profiles_client
    order = Order.new(user: @user, business_round: @round, client: client, kind: "invoice",
                      client_tax_profile: tax, cfdi_use: cfdi, client_receipt_profile: receipt)

    assert order.save, order.errors.full_messages.to_sentence

    assert_nil order.client_receipt_profile_id
    assert_equal tax.id, order.client_tax_profile_id
    assert_equal cfdi.id, order.cfdi_use_id
  end

  test "cambiar de factura a remisión limpia el perfil fiscal ya guardado" do
    client, tax, receipt, cfdi = profiles_client
    order = Order.create!(user: @user, business_round: @round, client: client, kind: "invoice",
                          client_tax_profile: tax, cfdi_use: cfdi)

    assert order.update(kind: "remission", client_receipt_profile: receipt)

    assert_nil order.reload.client_tax_profile_id
    assert_nil order.cfdi_use_id
  end
end
