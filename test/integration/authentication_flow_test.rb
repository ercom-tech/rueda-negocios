require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(erp_person_id: 1, username: "tester", password: "secret123", active: true)
    # El capturista solo puede entrar con una rueda cargada (guard de sesión);
    # aquí se prueba la mecánica de autenticación, así que se le da una.
    BusinessRound.create!(erp_round_id: 1, name: "Rueda Test", active: true)
  end

  test "root sin sesión redirige a login" do
    get root_path
    assert_redirected_to login_path
  end

  test "login con credenciales válidas entra" do
    post login_path, params: { username: "tester", password: "secret123" }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  test "login con contraseña incorrecta no entra" do
    post login_path, params: { username: "tester", password: "mala" }
    assert_response :unprocessable_entity
    get root_path
    assert_redirected_to login_path
  end

  test "usuario inactivo no puede entrar" do
    @user.update!(active: false)
    post login_path, params: { username: "tester", password: "secret123" }
    assert_response :unprocessable_entity
  end

  test "logout cierra la sesión" do
    post login_path, params: { username: "tester", password: "secret123" }
    delete logout_path
    assert_redirected_to login_path
    get root_path
    assert_redirected_to login_path
  end
end
