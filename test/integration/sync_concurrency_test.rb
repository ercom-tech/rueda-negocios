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
    post login_path, params: { username: "srv920", password: "secret123" }
  end

  test "con una transmisión corriendo no se puede lanzar una descarga" do
    SyncRun.create!(kind: "up", started_at: Time.current)

    post server_sync_down_path
    assert_redirected_to root_path
    assert_match(/corrida de sync en curso/, flash[:alert])
    assert_equal 0, SyncRun.down.count, "no debe crear el run de descarga"
  end

  test "con una descarga corriendo no se puede lanzar una transmisión" do
    SyncRun.create!(kind: "down", started_at: Time.current)

    post server_sync_up_path
    assert_redirected_to root_path
    assert_match(/corrida de sync en curso/, flash[:alert])
    assert_equal 0, SyncRun.up.count, "no debe crear el run de transmisión"
  end

  test "con una corrida corriendo el menú bloquea obtener, transmitir y cerrar" do
    SyncRun.create!(kind: "down", started_at: Time.current)

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
