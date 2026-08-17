require "test_helper"

# No se descarga con pedidos capturados sin transmitir: el replace del
# sync-down borraría ventas reales que aún no llegan al ERP.
#
# Homologado con "Cerrar rueda" y "Transmitir pedidos": el aviso llega en el
# toast al confirmar y NO se crea el SyncRun — antes se creaba la corrida, el
# job reventaba con la guarda y quedaba registrada como corrida FALLIDA por
# una condición previa que nunca llegó a intentarse.
class SyncDownPendingGuardTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(erp_person_id: 970, username: "srv970", password: "secret123",
                 role: "server", active: true)
    @cap    = User.create!(erp_person_id: 971, username: "cap971", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 970, name: "Rueda 970", active: true)
    @client = Client.create!(erp_client_key: "C970", name: "Cliente 970")
    Setting.instance.update!(selected_round_erp_id: 970, selected_round_name: "Rueda 970")
    post login_path, params: { username: "srv970", password: "secret123" }
  end

  def captured_untransmitted!
    Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission",
                  status: "captured", local_folio: "RN-000970")
  end

  test "con pedidos sin transmitir no se lanza la descarga y el toast dice por qué" do
    captured_untransmitted!

    post server_sync_down_path

    assert_redirected_to root_path
    assert_match(/Hay 1 pedido sin transmitir y se perdería al obtener la información\./, flash[:alert])
    # La alternativa de descartar existe porque un pedido atorado en la
    # colisión del 422 jamás va a transmitirse (6ª auditoría).
    assert_match(/Transmítelo \(o pide a su capturista que lo descarte\) y vuelve a intentar/, flash[:alert])
    assert_equal 0, SyncRun.down.count, "una condición previa no debe dejar una corrida fallida"
  end

  test "sin pedidos pendientes la descarga arranca normal" do
    post server_sync_down_path

    assert_redirected_to root_path
    assert_match(/Obteniendo la información/, flash[:notice])
    assert_equal 1, SyncRun.down.count
  end

  # Un solo aviso con el camino completo: el orden está forzado (con borradores
  # tampoco se puede transmitir), así que el operador debe verlo desde el
  # primer intento en vez de descubrirlo de mensaje en mensaje.
  test "con borradores Y pendientes el aviso enseña los dos pasos" do
    Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission")
    captured_untransmitted!

    post server_sync_down_path

    assert_match(/Hay 1 pedido en borrador y 1 sin transmitir/, flash[:alert])
    assert_match(/terminen o descarten los borradores, transmite los demás/, flash[:alert])
    assert_equal 0, SyncRun.down.count
  end

  # Un transmitido ya vive en el ERP: el replace lo purga sin pérdida.
  test "un transmitido no impide la descarga" do
    Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission",
                  status: "transmitted", erp_folio: "1A0001", local_folio: "RN-000971")

    post server_sync_down_path

    assert_match(/Obteniendo la información/, flash[:notice])
    assert_equal 1, SyncRun.down.count
  end

  # Un borrador SÍ: el replace lo borraría en silencio (misma regla que el
  # sync-up — con borradores no se sincroniza, ni para arriba ni para abajo).
  test "un borrador impide la descarga y el toast explica que se perdería" do
    Order.create!(user: @cap, business_round: @round, client: @client, kind: "remission")

    post server_sync_down_path

    assert_redirected_to root_path
    assert_match(/Hay 1 pedido en borrador y se perdería al obtener la información\./, flash[:alert])
    assert_match(/Pide que lo terminen o lo descarten/, flash[:alert])
    assert_equal 0, SyncRun.down.count
  end

  test "tras transmitir el pedido pendiente la descarga ya procede" do
    pending_order = captured_untransmitted!
    post server_sync_down_path
    assert_equal 0, SyncRun.down.count

    pending_order.update!(status: "transmitted", erp_folio: "1A0002", transmitted_at: Time.current)

    post server_sync_down_path
    assert_match(/Obteniendo la información/, flash[:notice])
    assert_equal 1, SyncRun.down.count
  end
end
