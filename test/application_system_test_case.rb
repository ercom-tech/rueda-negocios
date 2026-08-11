require "test_helper"

# Base de las pruebas de sistema (navegador real).
#
# Existen por una razón concreta: el proyecto acumuló JavaScript hecho a mano
# con lógica de verdad —calendario de rango, autocompletado, combo custom, paso
# por múltiplos del empaque, director de foco, modales— y hasta ahora todo eso
# se validaba a mano en el navegador. Ahí ya se escaparon defectos que ninguna
# prueba de integración podía ver, porque viven en la interacción entre Turbo,
# idiomorph y Stimulus, no en la respuesta del servidor.
#
# Chrome headless: la laptop del evento no tiene pantalla y la suite corre en
# consola. `selenium-webdriver` resuelve el driver solo (Selenium Manager), así
# que no hace falta chromedriver en el PATH.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Las pruebas de sistema corren el servidor en OTRO hilo con su propia
  # conexión, así que la transacción del test no lo alcanza. Rails lo resuelve
  # compartiendo la conexión (`use_transactional_tests` sigue en true), pero el
  # paralelismo sí estorba: dos navegadores contra la misma BD se pisan.
  parallelize(workers: 1)

  def sign_in(user, password: "secret123")
    visit login_path
    fill_in "Usuario", with: user.username
    fill_in "Contraseña", with: password
    click_button "Iniciar sesión"
    assert_text "Hola, #{user.username}"
  end
end
