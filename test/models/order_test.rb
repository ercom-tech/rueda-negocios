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
    codigos = order.order_items.reload.map(&:id)

    order.renumber_items!

    assert_equal codigos, order.order_items.reload.map(&:id), "no debe reordenar las partidas"
    assert_equal [ 1, 2, 3 ], order.order_items.map(&:position)
  end
end
