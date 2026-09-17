require "test_helper"

# El predicado que decide quién puede resolver un borrador ajeno, probado
# directamente.
#
# Hace falta aparte porque en una prueba de integración es INVISIBLE: a un
# capturista lo frena antes `accessible_orders` —solo ve sus pedidos—, así que
# quitarle la condición del rol a `can_resolve_draft?` deja la suite entera en
# verde (comprobado con una mutación). La condición es la segunda capa de la
# defensa, y esta prueba es la única que la sostiene.
class CanResolveDraftTest < ActiveSupport::TestCase
  setup do
    @server = User.create!(erp_person_id: 970_001, username: "srv_pred", password: "x", role: "server")
    @cap    = User.create!(erp_person_id: 970_002, username: "cap_pred", password: "x", role: "capturista")
    round   = BusinessRound.create!(erp_round_id: 970_001, name: "R", active: true)
    client  = Client.create!(erp_client_key: "PRD01", name: "C")
    @draft  = Order.new(user: @cap, business_round: round, client: client, kind: "remission")
    @draft.save!
    @captured = Order.create!(user: @cap, business_round: round, client: client, kind: "remission",
                              status: "captured", local_folio: "RN-970001")
  end

  def as(user)
    controller = ApplicationController.new
    controller.define_singleton_method(:current_user) { user }
    controller
  end

  test "el servidor resuelve un borrador" do
    assert as(@server).send(:can_resolve_draft?, @draft)
  end

  test "un capturista NO resuelve borradores, ni siquiera el suyo" do
    assert_not as(@cap).send(:can_resolve_draft?, @draft),
               "el dueño ya tiene can_edit_order?; este permiso es del equipo-servidor"
  end

  test "sin sesión, nadie resuelve nada" do
    assert_not as(nil).send(:can_resolve_draft?, @draft)
  end

  # Un capturado ya tiene folio y es transmisible: borrarlo es otra decisión,
  # y no la que desbloquea las operaciones del panel.
  test "el servidor NO resuelve un pedido ya capturado" do
    assert_not as(@server).send(:can_resolve_draft?, @captured)
  end
end
