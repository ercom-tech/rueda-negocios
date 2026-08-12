require "application_system_test_case"

# El paso 1 en un navegador de verdad: los combos son custom (botón + panel),
# así que su comportamiento vive todo en Stimulus y no se ve desde una prueba
# de integración.
class OrderHeaderTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 960_101, username: "cap_hdr", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 960_101, name: "Rueda encabezado", active: true)
    supplier = Supplier.create!(erp_supplier_id: 960_101, name: "PROVEEDOR HDR")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: supplier)

    @client = Client.create!(erp_client_key: "HDR01", name: "CLIENTE ENCABEZADO")
    cfdi = CfdiUse.create!(code: "G01", description: "ADQUISICIÓN DE MERCANCÍAS")
    # DOS razones sociales: con una sola el encabezado la preselecciona y no
    # habría campo faltante que provocar. Con su uso de CFDI por omisión, para
    # cubrir el caso que duplicaba el defecto: elegir la razón social auto-llena
    # el CFDI, así que quedaban DOS campos llenos y los dos seguían en rojo.
    ClientTaxProfile.create!(client: @client, rfc: "AAA010101AAA", business_name: "RAZON UNO",
                             default_cfdi_use: cfdi)
    ClientTaxProfile.create!(client: @client, rfc: "BBB020202BBB", business_name: "RAZON DOS",
                             default_cfdi_use: cfdi)
    ClientBranch.create!(client: @client, erp_branch_id: 1, name: "MATRIZ", is_default: true)
  end

  # Tras un submit inválido el combo queda con anillo rojo. Al elegir el valor
  # que faltaba, el anillo se quedaba puesto y el banner "Faltan datos
  # obligatorios" intacto: el capturista corregía, veía todo igual de rojo,
  # dudaba si había guardado y volvía a abrir el combo a verificar.
  test "corregir el campo que faltaba apaga su marca y el aviso" do
    sign_in @user
    visit new_order_path(client_key: @client.erp_client_key)

    click_button "Continuar a levantamiento de pedido"

    assert_text "Faltan datos obligatorios"
    assert_selector "button.ring-red-500"

    # Elegir la razón social que faltaba (auto-llena también el uso de CFDI).
    find("button[aria-label='Nombre o razón social (RFC)']").click
    click_button "BBB020202BBB — RAZON DOS"

    assert_no_selector "button.ring-red-500"
    assert_no_text "Faltan datos obligatorios"
  end

  # Apagar un campo no debe esconder el aviso si otro sigue faltando. Se usa
  # una razón social SIN uso de CFDI por omisión: al elegirla, el CFDI no se
  # auto-llena y sigue pendiente.
  test "el aviso sigue mientras quede algún campo marcado" do
    ClientTaxProfile.create!(client: @client, rfc: "CCC030303CCC", business_name: "RAZON SIN CFDI")

    sign_in @user
    visit new_order_path(client_key: @client.erp_client_key)
    click_button "Continuar a levantamiento de pedido"

    assert_text "Faltan datos obligatorios"

    find("button[aria-label='Nombre o razón social (RFC)']").click
    click_button "CCC030303CCC — RAZON SIN CFDI"

    assert_selector "button[aria-label='Uso de CFDI'].ring-red-500", wait: 1
    assert_text "Faltan datos obligatorios"
  end
end
