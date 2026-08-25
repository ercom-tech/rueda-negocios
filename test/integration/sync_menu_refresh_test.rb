require "test_helper"

# El panel PIDE su estado, no solo lo espera.
#
# El broadcast de `SyncRun` se pierde en el caso más común del evento: al
# lanzar un sync el controlador responde con un redirect, el navegador navega,
# y esa navegación tira la suscripción de Action Cable mientras abre otra. Una
# corrida que termina en menos de un segundo —lo normal con pocos pedidos—
# emite su broadcast dentro de ese hueco, y con el adaptador `async` no hay
# retención ni reenvío al que llega tarde. El panel se quedaba en "en
# progreso" indefinidamente y solo recargar lo destrababa (2026-08-25).
class SyncMenuRefreshTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(erp_person_id: 981, username: "srv981", password: "secret123",
                 role: "server", active: true)
    User.create!(erp_person_id: 982, username: "cap982", password: "secret123",
                 role: "capturista", active: true)
    Setting.instance.update!(selected_round_erp_id: 981, selected_round_name: "Rueda 981")
  end

  test "devuelve el menú como turbo stream" do
    login_as "srv981"

    get server_menu_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/turbo-stream action="replace" target="server-menu"/, response.body)
  end

  # El sondeo se enciende y se apaga con este atributo: es lo que evita que el
  # panel siga preguntando para siempre, y también lo que evita el bucle (cada
  # respuesta reemplaza el div y reconecta el controller).
  test "el menú anuncia si hay una corrida viva" do
    login_as "srv981"
    run = SyncRun.create!(kind: "up", started_at: Time.current, pid: Process.pid)

    get server_menu_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match(/data-sync-status-busy-value="true"/, response.body)

    run.finish!(status: :completed, summary: { transmitted: [], failed: [] })

    get server_menu_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match(/data-sync-status-busy-value="false"/, response.body)
  end

  # El escenario completo: el panel se pintó con la corrida viva y el broadcast
  # se perdió. La siguiente consulta tiene que traer ya el estado cerrado.
  test "tras cerrarse la corrida, el menú pedido refleja que terminó" do
    login_as "srv981"
    run = SyncRun.create!(kind: "up", started_at: Time.current, pid: Process.pid)

    get root_path
    assert_match(/data-sync-status-busy-value="true"/, response.body,
                 "el panel se pinta con la corrida viva")

    run.finish!(status: :completed, summary: { transmitted: [ { local: "RN-000001", erp: "1A0007" } ], failed: [] })

    get server_menu_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match(/data-sync-status-busy-value="false"/, response.body)
    assert_no_match(/data-sync-status-busy-value="true"/, response.body)
  end

  test "un capturista no puede pedir el menú del servidor" do
    login_as "cap982"

    get server_menu_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :redirect
  end

  test "sin sesión tampoco" do
    get server_menu_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :redirect
  end
end
