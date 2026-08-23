require "application_system_test_case"

# El combo custom del paso 1 abierto cerca del borde inferior. El panel es
# `absolute`, así que la página NO crece para hacerle sitio, y el shell del
# sitio recorta lo que se sale (`overflow-hidden`, para contener el patrón de
# herramientas). El resultado era un panel cortado, sin scroll con el que
# llegar a las opciones de abajo.
#
# Solo se ve en navegador: la integración no tiene layout, y sin medir rects
# la lista "está" en el DOM aunque nadie pueda verla ni tocarla.
class HeaderComboTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_401, username: "cap_combo_sys", password: "secret123",
                          role: "capturista", active: true)
    round  = BusinessRound.create!(erp_round_id: 970_401, name: "Rueda combo", active: true)
    Setting.instance.update!(selected_round_erp_id: 970_401, selected_round_name: "Rueda combo")
    cfdi = CfdiUse.create!(code: "G01", description: "Adquisición de mercancías")
    # Los seis montos del catálogo del ERP: con menos, el panel cabe y no hay
    # nada que probar.
    [ 5_000, 10_000, 20_000, 50_000, 100_000, 200_000 ].each_with_index do |amount, i|
      DivideAmount.create!(erp_consecutive: i + 1, amount: amount)
    end
    client = Client.create!(erp_client_key: "CB01", name: "Cliente combo")
    client.tax_profiles.create!(rfc: "XAXX010101000", business_name: "PUBLICO EN GENERAL",
                               default_cfdi_use: cfdi, is_default: false)
    client.branches.create!(erp_branch_id: 1, name: "MATRIZ", address: "CALLE 1", is_default: true)
    BusinessRoundClient.create!(business_round: round, client: client)
    @order = Order.create!(user: @user, business_round: round, client: client, kind: "invoice",
                           client_tax_profile: client.tax_profiles.first, cfdi_use: cfdi,
                           client_branch: client.branches.first, dividir_facturas: 0)
  end

  # Cuenta las opciones que caben ENTERAS dentro del panel y del shell: una
  # opción presente en el DOM pero recortada no sirve de nada.
  VISIBLE_OPTIONS = <<~JS.freeze
    const button = [...document.querySelectorAll("[aria-haspopup='listbox']")]
      .find((b) => b.getAttribute("aria-label").startsWith(arguments[0]))
    const panel = button.closest("[data-controller='select']")
      .querySelector("[data-select-target='panel']")
    const p = panel.getBoundingClientRect()
    const shell = document.querySelector(".overflow-hidden").getBoundingClientRect()
    const floor = Math.min(p.bottom, shell.bottom), ceiling = Math.max(p.top, shell.top)
    const options = [...panel.querySelectorAll("[role='option']")]
    return {
      total: options.length,
      visible: options.filter((o) => {
        const r = o.getBoundingClientRect()
        return r.bottom <= floor + 0.5 && r.top >= ceiling - 0.5
      }).length,
      flipped: panel.className.includes("bottom-full")
    }
  JS

  def open_combo(label)
    find("button[aria-label^='#{label}']").click
    page.evaluate_script("(function(){#{VISIBLE_OPTIONS}})('#{label}')")
  end

  test "el combo del último campo se abre completo aunque no quepa abajo" do
    sign_in @user
    visit edit_order_path(@order)

    result = open_combo("Dividir facturas")

    assert_equal 6, result["total"]
    assert_equal result["total"], result["visible"],
                 "el panel se está cortando: #{result['visible']} de #{result['total']} opciones a la vista"
    assert result["flipped"], "sin espacio abajo, el panel debe abrirse hacia arriba"
  end

  # El volteo es la excepción, no la regla: un combo con sitio de sobra debajo
  # tiene que seguir abriendo hacia abajo, que es donde el usuario lo espera.
  test "un combo con espacio de sobra sigue abriendo hacia abajo" do
    sign_in @user
    visit edit_order_path(@order)

    result = open_combo("Uso de CFDI")

    assert_equal result["total"], result["visible"]
    assert_not result["flipped"]
  end

  # En una ventana baja no alcanza ninguna de las dos direcciones: el panel se
  # acota al espacio real y se recorre con su propio scroll, en vez de
  # desbordar por debajo del shell donde no hay forma de llegar.
  test "en una ventana baja el panel se acota en vez de desbordar" do
    page.driver.browser.manage.window.resize_to(1400, 620)
    sign_in @user
    visit edit_order_path(@order)

    result = open_combo("Dividir facturas")

    assert_operator result["visible"], :>, 0, "algo debe quedar a la vista"
    assert_equal result["total"], result["visible"] + scrolled_out_count,
                 "las opciones que no se ven deben estar dentro del scroll del panel"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # Las que no se ven no están cortadas por el shell: están debajo del scroll
  # del propio panel, y se llega a ellas.
  def scrolled_out_count
    page.evaluate_script(<<~JS)
      (function(){
        const panel = document.querySelector("[data-select-target='panel']:not([hidden])")
        const p = panel.getBoundingClientRect()
        return [...panel.querySelectorAll("[role='option']")]
          .filter((o) => o.getBoundingClientRect().bottom > p.bottom + 0.5).length
      })()
    JS
  end
end
