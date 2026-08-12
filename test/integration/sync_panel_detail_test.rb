require "test_helper"

# Lo que el panel del servidor le dice al operador cuando una corrida no salió
# limpia. Los tres datos que se prueban aquí YA se calculaban y no se mostraban
# en ninguna pantalla: los motivos de los pedidos rechazados, los capturistas
# que quedaron sin proveedor ni marca, y los pedidos que el reemplazo quitó de
# la laptop. Sin ellos el operador reintenta a ciegas o cree que perdió el día.
class SyncPanelDetailTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(erp_person_id: 980, username: "srv980", password: "secret123",
                 role: "server", active: true)
    Setting.instance.update!(selected_round_erp_id: 980, selected_round_name: "Rueda 980")
    post login_path, params: { username: "srv980", password: "secret123" }
  end

  def up_run!(transmitted: [], failed: [])
    SyncRun.create!(kind: "up", started_at: 1.minute.ago, finished_at: Time.current,
                    status: "failed", summary: { transmitted: transmitted, failed: failed })
  end

  def down_run!(summary)
    SyncRun.create!(kind: "down", started_at: 1.minute.ago, finished_at: Time.current,
                    status: "completed", summary: { entities: {} }.merge(summary))
  end

  # --- Transmisión parcial -------------------------------------------------

  test "el panel lista el folio y el motivo de cada pedido rechazado" do
    up_run!(transmitted: [ { local: "RN-000001", erp: "1A0007" } ],
            failed: [ { local: "RN-000002", status: "422",
                        error: "El cliente ABAISM no existe en el ERP" } ])

    get root_path

    assert_response :success
    assert_match(/RN-000002/, response.body)
    assert_match(/El cliente ABAISM no existe en el ERP/, response.body)
  end

  # "✗ Falló" a secas leía como "no pasó nada" aunque hubiera pedidos ya
  # insertados en el ERP — el operador no sabía si retransmitir era seguro.
  test "con transmisión parcial el panel dice cuántos SÍ entraron" do
    up_run!(transmitted: [ { local: "RN-000001", erp: "1A0007" },
                           { local: "RN-000003", erp: "1A0008" } ],
            failed: [ { local: "RN-000002", status: "422", error: "rechazado" } ])

    get root_path

    assert_match(/Parcial/, response.body)
    assert_match(/2 pedidos transmitidos/, response.body)
    assert_match(/1 sin transmitir/, response.body)
  end

  test "sin ningún pedido transmitido el rótulo sigue siendo Falló" do
    up_run!(failed: [ { local: "RN-000002", status: "422", error: "rechazado" } ])

    get root_path

    assert_match(/Falló/, response.body)
    assert_no_match(/Parcial/, response.body)
  end

  # Un tope silencioso se leería como "esos son todos".
  test "con muchos rechazos se listan los primeros y se dice cuántos faltan" do
    failures = (1..7).map { |i| { local: format("RN-%06d", i), status: "422", error: "motivo #{i}" } }
    up_run!(failed: failures)

    get root_path

    assert_match(/RN-000001/, response.body)
    assert_match(/y 3 más/, response.body)
    assert_no_match(/RN-000007/, response.body)
  end

  # `parse_error` guarda el cuerpo crudo cuando la respuesta viene rota.
  test "un cuerpo de respuesta con marcado no se pinta como marcado" do
    up_run!(failed: [ { local: "RN-000002", status: "500", error: "<html>502 Bad Gateway</html>" } ])

    get root_path

    assert_match(/502 Bad Gateway/, response.body)
    assert_no_match(%r{<html>502}, response.body)
  end

  test "el panel avisa de los pedidos que se editaron durante su transmisión" do
    SyncRun.create!(kind: "up", started_at: 1.minute.ago, finished_at: Time.current,
                    status: "completed",
                    summary: { transmitted: [ { local: "RN-000001", erp: "1A0007" } ],
                               conflicts: [ { local: "RN-000001", erp: "1A0007" } ] })

    get root_path

    assert_match(/Revisa este pedido contra el ERP/, response.body)
    assert_match(/RN-000001 → 1A0007/, response.body)
  end

  # Basta un pedido fallido para que la corrida entera quede "Parcial", y el
  # bloque de conflictos vivía solo en la rama `completed`: la combinación
  # conflicto + fallo —la más probable, ambos delatan una sesión con
  # problemas— se tragaba el aviso. (5ª auditoría.)
  test "el aviso de editados durante la transmisión también sale en corrida parcial" do
    SyncRun.create!(kind: "up", started_at: 1.minute.ago, finished_at: Time.current,
                    status: "failed",
                    summary: { transmitted: [ { local: "RN-000001", erp: "1A0007" } ],
                               failed: [ { local: "RN-000002", status: "422", error: "rechazado" } ],
                               conflicts: [ { local: "RN-000001", erp: "1A0007" } ] })

    get root_path

    assert_match(/Parcial/, response.body)
    assert_match(/Revisa este pedido contra el ERP/, response.body)
    assert_match(/RN-000001 → 1A0007/, response.body)
  end

  # --- Sync-down: lo que la corrida hizo y no se veía ------------------------

  test "el panel avisa de los capturistas que quedaron sin proveedor ni marca" do
    down_run!(skipped_people: 2)

    get root_path

    assert_match(/2 capturistas/, response.body)
    assert_match(/sin proveedor ni marca/, response.body)
  end

  # El dato siempre quedó guardado en la corrida; solo la tarea de consola lo
  # mostraba, y el operador trabaja con el panel: el capturista con contraseña
  # ilegible llegaba invisible al evento, donde ya no tiene arreglo. (5ª aud.)
  test "el panel avisa de los capturistas cuya contraseña no sirve" do
    down_run!(skipped_users: [ "makita1" ])

    get root_path

    assert_match(/1 capturista/, response.body)
    assert_match(/no va a poder entrar \(su contraseña no sirve\)/, response.body)
    assert_match(/makita1/, response.body)
    assert_match(/restablezcan la contraseña/, response.body)
  end

  test "el panel dice qué capturistas quitó el reemplazo" do
    down_run!(removed_users: [ "cap1", "cap2" ])

    get root_path

    assert_match(/Se quitaron/, response.body)
    assert_match(/2 capturistas/, response.body)
    assert_match(/cap1, cap2/, response.body)
  end

  # El aviso de lo que se quitó va en el modal, ANTES de confirmar, que es
  # cuando le sirve al operador — no en el resumen de lo ya hecho.
  test "el panel no informa de los pedidos que quitó el reemplazo" do
    down_run!(purged_orders: 5)

    get root_path

    assert_no_match(/5 pedidos ya transmitidos/, response.body)
  end

  # La salida ante una corrida muerta ya no es reiniciar el servidor: al
  # volver al menú, el barrido cierra lo que no tiene proceso vivo y el panel
  # se desbloquea. (5ª auditoría.)
  test "una corrida cuyo proceso murió se recupera al volver al menú" do
    dead = Process.spawn("true")
    Process.wait(dead)
    run = SyncRun.create!(kind: "up", started_at: 1.minute.ago, pid: dead)

    get root_path

    assert run.reload.failed?
    assert_match(/se quedó a medias/, run.message)
  end

  test "una corrida limpia no pinta el bloque de avisos" do
    down_run!(skipped_people: 0, purged_orders: 0)

    get root_path

    assert_no_match(/sin proveedor ni marca/, response.body)
  end

  # --- El modal de confirmación dice qué se va a borrar ----------------------

  test "el modal de obtener información nombra los pedidos que se van a quitar" do
    cap    = User.create!(erp_person_id: 981, username: "cap981", password: "secret123",
                          role: "capturista", active: true)
    round  = BusinessRound.create!(erp_round_id: 980, name: "Rueda 980", active: true)
    client = Client.create!(erp_client_key: "C980", name: "Cliente 980")
    2.times do |i|
      Order.create!(user: cap, business_round: round, client: client, kind: "remission",
                    status: "transmitted", local_folio: format("RN-%06d", 980 + i),
                    erp_folio: "1A000#{i}", transmitted_at: Time.current)
    end

    get root_path

    assert_match(/Se quitarán 2 pedidos ya transmitidos/, response.body)
  end

  test "sin pedidos en la laptop el modal no habla de quitar nada" do
    get root_path

    assert_match(/se reemplazará la información local/, response.body)
    assert_no_match(/Se quitarán/, response.body)
  end
end
