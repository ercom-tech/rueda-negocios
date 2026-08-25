require "application_system_test_case"

# El panel del servidor se destraba SOLO cuando el broadcast no llega.
#
# Es el defecto que se vio en la laptop (2026-08-25): se lanza una
# transmisión, el controlador responde con un redirect, el navegador navega —y
# esa navegación tira la suscripción de Action Cable mientras abre otra—, la
# corrida termina en menos de un segundo y su broadcast cae en ese hueco. Con
# el adaptador `async` no hay reenvío al que llega tarde, así que el panel se
# quedaba en "en progreso" indefinidamente y solo recargar lo destrababa.
#
# Cómo se reproduce el mensaje perdido: cerrando la corrida con
# `update_columns`, que NO dispara el `after_update_commit` de SyncRun y por
# tanto no emite ningún broadcast. El estado cambia en el servidor y el
# navegador no se entera por el cable — que es exactamente lo que pasa en la
# laptop cuando el mensaje sale mientras la suscripción se está reabriendo.
#
# El `finish!` normal NO sirve para esto: en una prueba de sistema el servidor
# vive en el mismo proceso que el test y el adaptador `test` de Action Cable
# hereda de `Async`, así que el broadcast SÍ se entrega. Con `finish!` esta
# prueba pasa igual sin el controller — comprobado quitándolo.
class SyncMenuRefreshTest < ApplicationSystemTestCase
  setup do
    @server = User.create!(erp_person_id: 983_101, username: "srv_menu", password: "secret123",
                           role: "server", active: true)
    Setting.instance.update!(selected_round_erp_id: 983_101, selected_round_name: "Rueda menú")
  end

  test "el panel refleja el fin de la corrida sin recargar ni broadcast" do
    run = SyncRun.create!(kind: "up", started_at: Time.current, pid: Process.pid)

    sign_in @server
    visit root_path

    # Punto de partida: bloqueado, como lo ve el operador al lanzar el sync.
    assert_selector "#server-menu[data-sync-status-busy-value='true']"

    # La corrida termina del lado del servidor SIN emitir broadcast
    # (`update_columns` salta el after_update_commit). El navegador no tiene
    # forma de enterarse más que preguntando.
    run.update_columns(status: "completed", finished_at: Time.current,
                       summary: { transmitted: [], failed: [] })

    # Sin tocar nada: el sondeo lo trae. El tiempo de espera de Capybara cubre
    # de sobra el intervalo de 3 s del controller.
    assert_selector "#server-menu[data-sync-status-busy-value='false']", wait: 10
    assert_text "Listo"
  end

  # La otra mitad, y la que evita un remedio peor: cada respuesta reemplaza el
  # div y RECONECTA el controller, así que un refresh incondicional al conectar
  # se realimentaría en un bucle infinito de peticiones contra la laptop que
  # está sirviendo la captura de todo el salón.
  test "sin corrida viva el panel no sondea" do
    sign_in @server
    visit root_path

    assert_selector "#server-menu[data-sync-status-busy-value='false']"

    # Si hubiera bucle, el contador de peticiones al endpoint crecería solo.
    # Se cuenta desde el propio navegador, envolviendo fetch.
    page.execute_script(<<~JS)
      window.__menuHits = 0
      const original = window.fetch
      window.fetch = function (...args) {
        if (String(args[0]).includes("/server/menu")) window.__menuHits += 1
        return original.apply(this, args)
      }
    JS

    sleep 4 # más que el intervalo del sondeo

    assert_equal 0, page.evaluate_script("window.__menuHits"),
                 "sin corrida viva no debe haber ni una consulta"
  end
end
