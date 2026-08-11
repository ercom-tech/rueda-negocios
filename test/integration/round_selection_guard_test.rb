require "test_helper"
require "webmock/minitest"

class RoundSelectionGuardTest < ActionDispatch::IntegrationTest
  setup do
    @server = User.create!(erp_person_id: 900, username: "srv", password: "secret123",
                           role: "server", active: true)
    post login_path, params: { username: "srv", password: "secret123" }
    # La lista de ruedas llama a rueda-api; con webmock activo hay que
    # stubearla (si RUEDA_API_URL no está configurada, el rescue del
    # controller también termina en render normal con lista vacía).
    stub_request(:get, %r{/ruedas$}).to_return(
      status: 200, body: "[]", headers: { "Content-Type" => "application/json" }
    )
  end

  def select_round!(erp_id: 3, name: "Oaxaca 2026")
    Setting.instance.update!(selected_round_erp_id: erp_id, selected_round_name: name)
  end

  test "sin rueda en curso, elegir rueda está disponible" do
    get server_rounds_path
    assert_response :success
  end

  test "la selección pide confirmación: modal con el PATCH y sus params adentro" do
    stub_request(:get, %r{/ruedas$}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: [ { erp_round_id: 7, name: "Rueda Nueva", year: 2026 } ].to_json
    )

    get server_rounds_path
    assert_response :success
    assert_select "div[data-controller=modal]" do
      assert_select "button[data-action='modal#open']", text: "Seleccionar"
      assert_select "div[data-modal-target=dialog]" do
        assert_select "form[action=?]", server_select_round_path do
          assert_select "input[name=erp_round_id][value='7']"
          assert_select "input[name=name][value='Rueda Nueva']"
        end
      end
    end
  end

  test "con rueda en curso, la lista de ruedas redirige al menú con alert" do
    select_round!

    get server_rounds_path
    assert_redirected_to root_path
    assert_match(/Oaxaca 2026/, flash[:alert])
  end

  test "con rueda en curso, no se puede guardar otra elección (URL directo)" do
    select_round!

    patch server_select_round_path, params: { erp_round_id: 5, name: "Otra rueda" }
    assert_redirected_to root_path
    assert_equal 3, Setting.instance.reload.selected_round_erp_id
    assert_equal "Oaxaca 2026", Setting.instance.selected_round_name
  end

  test "tras cerrar la rueda, elegir rueda se reabre" do
    select_round!
    Sync::CloseRound.run!

    get server_rounds_path
    assert_response :success
  end

  # Hallazgo de la 3ª auditoría: esta pantalla armaba su propio encabezado (sin
  # barra superior) y pintaba las ruedas en paneles translúcidos `bg-white/5`,
  # que sobre el fondo con patrón se lavan — las dos cosas contra
  # `docs/convenciones-visuales.md`.
  test "usa el shell único y superficies crema, no paneles translúcidos" do
    stub_request(:get, %r{/ruedas$}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: [ { erp_round_id: 7, name: "Rueda Nueva", year: 2026 } ].to_json
    )

    get server_rounds_path
    assert_response :success
    assert_match(/Usuario:/, response.body, "debe usar la barra superior compartida")
    assert_match(/Cerrar sesión/, response.body)
    assert_match(/lg:px-\[5%\]/, response.body, "margen lateral del shell")
    assert_match(/bg-brand-cream/, response.body, "la card de rueda va en crema")
    assert_no_match(/bg-white\/5/, response.body, "sin paneles translúcidos")
  end
end
