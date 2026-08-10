require "test_helper"

# No se transmite mientras haya pedidos en borrador: el sync-up solo toma
# `captured`, así que transmitir con borradores vivos deja al operador creyendo
# que ya todo llegó al ERP — y cerrar la rueda los purga.
#
# Patrón de "Cerrar rueda" (decisión del usuario): la card NO se bloquea; el
# modal de confirmación aparece normal y el motivo se avisa en el toast al
# confirmar.
class SyncUpDraftsGuardTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(erp_person_id: 960, username: "srv960", password: "secret123",
                 role: "server", active: true)
    @cap    = User.create!(erp_person_id: 961, username: "cap961", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 960, name: "Rueda 960", active: true)
    @client = Client.create!(erp_client_key: "C960", name: "Cliente 960")
    Setting.instance.update!(selected_round_erp_id: 960, selected_round_name: "Rueda 960")
    post login_path, params: { username: "srv960", password: "secret123" }
  end

  def draft!
    Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission")
  end

  def captured!
    Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission",
                  status: "captured", local_folio: "RN-000960")
  end

  test "con un borrador no se lanza la transmisión y el toast dice por qué" do
    draft!

    post server_sync_up_path

    assert_redirected_to root_path
    assert_match(/1 pedido\(s\) en borrador/, flash[:alert])
    assert_match(/finalizarse o descartarse/, flash[:alert])
    assert_equal 0, SyncRun.up.count, "una condición previa no debe dejar una corrida fallida"
  end

  test "sin borradores la transmisión arranca normal" do
    captured!

    post server_sync_up_path

    assert_redirected_to root_path
    assert_match(/Transmisión iniciada/, flash[:notice])
    assert_equal 1, SyncRun.up.count
  end

  # La card sigue habilitada: el aviso llega al confirmar, no antes (mismo
  # trato que "Cerrar rueda" con pedidos sin transmitir).
  test "el menú NO bloquea la card de transmitir por haber borradores" do
    draft!

    get root_path
    assert_response :success
    assert_select "#server-menu button[disabled]", count: 0
  end

  test "al finalizar el borrador la transmisión ya procede" do
    borrador = draft!
    post server_sync_up_path
    assert_equal 0, SyncRun.up.count

    borrador.update!(status: "captured", local_folio: "RN-000961")

    post server_sync_up_path
    assert_match(/Transmisión iniciada/, flash[:notice])
    assert_equal 1, SyncRun.up.count
  end
end
