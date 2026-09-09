require "test_helper"

# Lo que el panel del servidor DICE de una corrida. Es el camino del operador:
# la tarea de consola es el otro, y la convención del proyecto exige que todo
# dato nuevo del summary aterrice en los dos (ya se rompió en la 5ª y en la 7ª;
# esta prueba existe para que no vuelva a pasar en silencio).
class SyncPanelNoticesTest < ActionDispatch::IntegrationTest
  setup do
    @server = User.create!(erp_person_id: 983_301, username: "srv_notices", password: "secret123",
                           role: "server", active: true)
    BusinessRound.create!(erp_round_id: 3301, name: "Rueda 3301", active: true)
    Setting.instance.update!(selected_round_erp_id: 3301, selected_round_name: "Rueda 3301")
    login_as "srv_notices"
  end

  def finished_run(kind:, summary:)
    run = SyncRun.create!(kind: kind, started_at: 2.minutes.ago, pid: Process.pid)
    run.update!(status: :completed, finished_at: Time.current, summary: summary)
    run
  end

  # El pedido de la rueda entra al ERP partido, así que quien cuente allá
  # encuentra más pedidos de los que transmitió: sin esta línea se lee como
  # duplicación.
  test "el panel dice cuántos pedidos quedaron del lado del ERP" do
    finished_run(kind: "up", summary: {
                   transmitted: [ { local: "RN-000001", erp: "1A0005", erp_all: %w[1A0005 1A0006] },
                                  { local: "RN-000002", erp: "1A0007", erp_all: %w[1A0007] } ],
                   failed: []
                 })

    get server_menu_path

    assert_response :success
    assert_match(/2 pedidos transmitidos/, response.body)
    assert_match(/entraron al ERP como 3 pedidos/, response.body)
  end

  # Sin reparto no hay nada que explicar: la línea sobraría.
  test "sin pedidos partidos el panel no habla del ERP" do
    finished_run(kind: "up", summary: {
                   transmitted: [ { local: "RN-000001", erp: "1A0005", erp_all: %w[1A0005] } ], failed: []
                 })

    get server_menu_path

    assert_match(/1 pedido transmitido/, response.body)
    assert_no_match(/entraron al ERP como/, response.body)
  end

  # Compat: las corridas guardadas antes de que existiera `erp_all`.
  test "una corrida vieja sin la lista de folios no rompe el panel" do
    finished_run(kind: "up", summary: {
                   transmitted: [ { local: "RN-000001", erp: "1A0005" } ], failed: []
                 })

    get server_menu_path

    assert_response :success
    assert_no_match(/entraron al ERP como/, response.body)
  end

  test "el panel avisa cuando la rueda llegó sin clave de folios" do
    finished_run(kind: "down", summary: { entities: { products: 10 }, missing_folio_prefix: true })

    get server_menu_path

    assert_match(/no trae/, response.body)
    assert_match(/clave de folios/, response.body)
    assert_match(/RN-000123/, response.body)
  end

  test "con clave de folios el panel no levanta el aviso" do
    finished_run(kind: "down", summary: { entities: { products: 10 }, missing_folio_prefix: false })

    get server_menu_path

    assert_no_match(/clave de folios/, response.body)
  end
end
