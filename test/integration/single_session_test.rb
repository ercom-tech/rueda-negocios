require "test_helper"

# Sesión única por usuario: "el último login gana". Un login nuevo con el
# mismo usuario regenera el session_token, y la sesión anterior (cookie con
# token viejo) se cierra en su siguiente request.
class SingleSessionTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(erp_person_id: 930, username: "cap930", password: "secret123",
                 role: "capturista", active: true)
    BusinessRound.create!(erp_round_id: 930, name: "Rueda 930", active: true)
  end

  test "un segundo login desplaza a la sesión anterior" do
    device_a = open_session
    device_b = open_session

    login_as("cap930", session: device_a)
    device_a.get "/"
    device_a.assert_response :success

    login_as("cap930", session: device_b)

    device_a.get "/"
    device_a.assert_redirected_to "/login"
    assert_match(/otro equipo/, device_a.flash[:alert])
    device_a.get "/"
    device_a.assert_redirected_to "/login", "la sesión desplazada debe quedar cerrada"

    device_b.get "/"
    device_b.assert_response :success
  end

  test "la propia sesión sigue viva entre requests" do
    post login_path, params: { username: "cap930", password: "secret123" }

    get root_path
    assert_response :success
    get reports_path
    assert_response :success
  end

  test "el logout de una sesión desplazada no choca" do
    device_a = open_session
    device_b = open_session
    login_as("cap930", session: device_a)
    login_as("cap930", session: device_b)

    device_a.delete "/logout"
    device_a.assert_redirected_to "/login"

    # El logout de A no debe tumbar a B (cada quien su cookie; el token vive
    # en el usuario y solo lo regenera un login).
    device_b.get "/"
    device_b.assert_response :success
  end
end
