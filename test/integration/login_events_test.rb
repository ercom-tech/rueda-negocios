require "test_helper"

# Auditoría de inicios de sesión: cada intento (exitoso o no) deja un
# LoginEvent con quién, cuándo y desde dónde.
class LoginEventsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(erp_person_id: 950, username: "cap950", password: "secret123",
                         role: "capturista", active: true)
    BusinessRound.create!(erp_round_id: 950, name: "Rueda 950", active: true)
  end

  test "login exitoso registra evento con usuario, éxito e ip" do
    post login_path, params: { username: "cap950", password: "secret123" }

    event = LoginEvent.recent_first.first
    assert event.success?
    assert_equal @user, event.user
    assert_equal "cap950", event.username
    assert event.ip.present?
    assert event.created_at.present?
  end

  test "contraseña incorrecta registra evento fallido ligado al usuario" do
    post login_path, params: { username: "cap950", password: "mala" }

    event = LoginEvent.failed.recent_first.first
    assert_equal @user, event.user
    assert_equal "cap950", event.username
  end

  test "username inexistente registra el texto tecleado sin usuario" do
    post login_path, params: { username: "fantasma", password: "x" }

    event = LoginEvent.failed.recent_first.first
    assert_nil event.user_id
    assert_equal "fantasma", event.username
  end

  test "capturista bloqueado por falta de rueda queda como intento fallido" do
    BusinessRound.update_all(active: false)

    post login_path, params: { username: "cap950", password: "secret123" }

    event = LoginEvent.recent_first.first
    assert_not event.success?
    assert_equal @user, event.user
  end

  test "el evento sobrevive si el sync-down elimina al usuario" do
    post login_path, params: { username: "cap950", password: "secret123" }
    delete logout_path
    @user.destroy!

    event = LoginEvent.recent_first.first
    assert_nil event.reload.user_id, "la FK anula el usuario"
    assert_equal "cap950", event.username, "el evento permanece con el username"
  end
end
