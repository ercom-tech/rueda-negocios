require "test_helper"

# Con una corrida de sync viva (del tipo que sea) no se puede lanzar otra:
# una descarga a media transmisión (o viceversa) pisaría los datos del job en
# vuelo. El menú refleja el bloqueo (botones disabled) y los guards lo
# imponen por URL directo.
class SyncConcurrencyTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(erp_person_id: 920, username: "srv920", password: "secret123",
                 role: "server", active: true)
    Setting.instance.update!(selected_round_erp_id: 920, selected_round_name: "Rueda 920")
    login_as "srv920"
  end

  test "con una transmisión corriendo no se puede lanzar una descarga" do
    SyncRun.create!(kind: "up", started_at: Time.current)

    post server_sync_down_path
    assert_redirected_to root_path
    assert_match(/obteniendo información o transmitiendo pedidos/, flash[:alert])
    assert_equal 0, SyncRun.down.count, "no debe crear el run de descarga"
  end

  test "con una descarga corriendo no se puede lanzar una transmisión" do
    SyncRun.create!(kind: "down", started_at: Time.current)

    post server_sync_up_path
    assert_redirected_to root_path
    assert_match(/obteniendo información o transmitiendo pedidos/, flash[:alert])
    assert_equal 0, SyncRun.up.count, "no debe crear el run de transmisión"
  end

  # Hallazgo de la 3ª auditoría: el índice único de respaldo es POR TIPO, así
  # que solo impide dos `down` (o dos `up`) simultáneos — no un `down` y un
  # `up` a la vez, que es justo la combinación que corrompe datos (el replace
  # del down borra los pedidos que el up está transmitiendo). La exclusión
  # real la da `SyncRun.start`, que verifica y crea bajo un mismo lock.
  test "SyncRun.start no crea una corrida si ya hay otra viva, sea del tipo que sea" do
    SyncRun.create!(kind: "down", started_at: Time.current)

    assert_nil SyncRun.start("up"), "un up no debe arrancar con un down vivo"
    assert_nil SyncRun.start("down"), "ni otro down"
    assert_equal 1, SyncRun.count
  end

  test "SyncRun.start sí crea la corrida cuando no hay ninguna viva" do
    SyncRun.create!(kind: "down", started_at: 1.hour.ago).finish!(status: "completed")

    run = SyncRun.start("up")
    assert run.present?
    assert run.running?
    assert_equal 2, SyncRun.count, "una corrida terminada no bloquea"
  end

  # El índice único por tipo se conserva como red: dos altas del MISMO tipo en
  # carrera (dos POST casi simultáneos) chocan contra él y el controller lo
  # traduce a un aviso amigable.
  test "el índice único sigue cubriendo dos corridas del mismo tipo" do
    SyncRun.create!(kind: "up", started_at: Time.current)

    assert_raises(ActiveRecord::RecordNotUnique) do
      SyncRun.create!(kind: "up", started_at: Time.current)
    end
  end

  test "con una corrida corriendo el menú bloquea obtener, transmitir y cerrar" do
    # Con dueño vivo (pid): el barrido que corre al cargar el menú respeta las
    # corridas cuyo proceso existe y solo cierra las muertas.
    SyncRun.create!(kind: "down", started_at: Time.current, pid: Process.pid)

    get root_path
    assert_response :success
    assert_select "#server-menu button[disabled]", count: 3
  end

  test "sin corridas vivas el menú no bloquea nada" do
    SyncRun.create!(kind: "down", started_at: 1.hour.ago)
           .finish!(status: "completed")

    get root_path
    assert_response :success
    assert_select "#server-menu button[disabled]", count: 0
  end
end
