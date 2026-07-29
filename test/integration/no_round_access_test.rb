require "test_helper"

# Sin rueda en curso: los capturistas ni siquiera entran (login bloqueado y
# sesiones vivas expulsadas); el server entra pero solo puede elegir rueda
# (transmitir / reportes / cerrar quedan bloqueados también por URL directo).
class NoRoundAccessTest < ActionDispatch::IntegrationTest
  setup do
    @capturista = User.create!(erp_person_id: 910, username: "cap910", password: "secret123",
                               role: "capturista", active: true)
    @server     = User.create!(erp_person_id: 911, username: "srv911", password: "secret123",
                               role: "server", active: true)
  end

  def activate_round!
    BusinessRound.create!(erp_round_id: 910, name: "Rueda 910", active: true)
  end

  test "capturista no puede loguearse sin rueda cargada" do
    post login_path, params: { username: "cap910", password: "secret123" }

    assert_response :unprocessable_entity
    assert_match(/No hay rueda en curso/, flash[:alert])
    get root_path
    assert_redirected_to login_path, "no debe quedar sesión abierta"
  end

  test "capturista entra normal con rueda cargada" do
    activate_round!

    post login_path, params: { username: "cap910", password: "secret123" }
    assert_redirected_to root_path
  end

  test "server entra aunque no haya rueda (es quien la carga)" do
    post login_path, params: { username: "srv911", password: "secret123" }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  test "capturista con sesión viva es expulsado cuando la rueda se cierra" do
    round = activate_round!
    post login_path, params: { username: "cap910", password: "secret123" }

    round.update!(active: false) # lo que hace Cerrar rueda

    get root_path
    assert_redirected_to login_path
    assert_match(/No hay rueda en curso/, flash[:alert])
    get root_path
    assert_redirected_to login_path, "la sesión debe quedar cerrada"
  end

  test "server sin rueda: transmitir, cerrar rueda y reportes bloqueados por URL directo" do
    post login_path, params: { username: "srv911", password: "secret123" }

    post server_sync_up_path
    assert_redirected_to root_path
    assert_match(/No hay rueda en curso/, flash[:alert])
    assert_equal 0, SyncRun.count, "no debe crear corridas"

    post server_close_round_path
    assert_redirected_to root_path
    assert_match(/No hay rueda que cerrar/, flash[:alert])

    get reports_path
    assert_redirected_to root_path

    get captured_orders_report_path
    assert_redirected_to root_path
  end

  test "server con rueda seleccionada: reportes disponibles" do
    Setting.instance.update!(selected_round_erp_id: 910, selected_round_name: "Rueda 910")
    post login_path, params: { username: "srv911", password: "secret123" }

    get reports_path
    assert_response :success
  end
end
