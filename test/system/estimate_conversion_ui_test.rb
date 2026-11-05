require "application_system_test_case"

# "Convertir en pedido" en el navegador (18ª auditoría): lo que solo se ve con
# el DOM de por medio — qué capa queda encima del modal, si el modal se cierra
# cuando la acción no procede, y que la genérica pida confirmar.
class EstimateConversionUiTest < ApplicationSystemTestCase
  setup do
    @round = BusinessRound.create!(erp_round_id: 9811, name: "Rueda UI Conv", active: true)
    @user  = User.create!(erp_person_id: 9811, username: "cap_uiconv", password: "secret123",
                          role: "capturista", active: true)
    supplier = Supplier.create!(erp_supplier_id: 9811, name: "MAKITA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: supplier)
    Setting.instance.update!(selected_round_erp_id: 9811, selected_round_name: @round.name)
    @client  = Client.create!(erp_client_key: "UIC01", name: "CLIENTE UI")
    @receipt = @client.receipt_profiles.create!(name: "REMISION UI")
    @branch  = @client.branches.create!(erp_branch_id: 1, name: "MATRIZ", is_default: true)
    @drill   = Product.create!(erp_product_id: 981_101, description: "TALADRO UI", unit: "PZA", max_discount: 50)
    Price.create!(product: @drill, credit_wholesale_price: 1000, tax_rate: 16)
  end

  def estimate!(client: nil)
    estimate = Order.create!(user: @user, business_round: @round, document: "estimate", client: client,
                             kind: (client ? "remission" : nil), client_receipt_profile: (@receipt if client),
                             client_branch: (@branch if client))
    estimate.order_items.create!(@drill.to_order_item_attributes.merge(position: 1, quantity: 2, discount_percent: 0))
    estimate.capture!
    estimate
  end

  # El encabezado del resumen iba en `z-20` y el contenido en `z-10`: el modal
  # nuevo vive en el contenido, así que su `z-50` quedaba encerrado y la barra
  # superior se pintaba ENCIMA — "Cerrar sesión" respondía con el modal abierto.
  # Tablet horizontal, donde la barra y el modal se enciman.
  test "en el resumen, el modal de conversión queda encima de la barra superior" do
    estimate = estimate!(client: @client)
    sign_in @user
    page.driver.browser.manage.window.resize_to(1024, 600)
    visit summary_order_path(estimate)

    click_button "Convertir en pedido"
    dialog = find("[role=dialog]", text: "Se creará el pedido")
    logout = find_button("Cerrar sesión")

    top_at_logout = page.evaluate_script(<<~JS)
      (() => { const r = document.evaluate("//button[normalize-space()='Cerrar sesión']", document, null, 9, null)
                 .singleNodeValue.getBoundingClientRect();
               const el = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
               return !!el.closest("[role=dialog]"); })()
    JS
    assert top_at_logout, "el overlay del modal debe tapar 'Cerrar sesión'"
    assert dialog.visible?
    assert logout
  ensure
    # La sesión del navegador se reusa entre pruebas: sin regresar al tamaño
    # de la suite, la siguiente corría a 1024×600 y `header_combo_test`
    # fallaba según el orden (19ª auditoría).
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # Un sync vivo responde 422 con el aviso en el flash; el modal se quedaba
  # abierto encima de la pantalla (`_confirm_dialog` no se cerraba al terminar
  # su envío, como sí lo hace el de promoción).
  test "si la conversión no procede por un sync, el modal se cierra y queda el aviso" do
    estimate = estimate!(client: @client)
    sign_in @user
    visit order_path(estimate)
    SyncRun.create!(kind: "down", status: "running", pid: Process.pid, started_at: Time.current)

    click_button "Convertir en pedido"
    within("[role=dialog]") { click_button "Sí, convertir" }

    assert_text "Se está actualizando la información"
    assert_no_selector "[role=dialog]", visible: true
    assert Order.exists?(estimate.id)
  end

  # Con factura Y remisión, el tipo es un radio; Enter sobre él hacía el envío
  # implícito por el botón predeterminado del formulario — el "Sí, convertir"
  # del diálogo oculto — y convertía sin modal (19ª auditoría).
  test "Enter sobre el tipo de pedido no convierte sin confirmar" do
    cfdi = CfdiUse.create!(code: "G03", description: "Gastos en general")
    @client.tax_profiles.create!(rfc: "XAXX010101000", business_name: "PUBLICO EN GENERAL",
                                 default_cfdi_use: cfdi, is_default: false)
    estimate = estimate!
    sign_in @user
    visit conversion_order_path(estimate, client_key: "UIC01")

    find("input[type=radio][value=remission]").click
    find("input[type=radio][value=remission]").send_keys(:enter)

    assert_no_text "se convirtió en el pedido"
    assert_current_path conversion_order_path(estimate, client_key: "UIC01")
    assert Order.exists?(estimate.id)
  end

  # El cierre al terminar el envío vivía solo en la variante `button_to`: el
  # paso 1 de la genérica lo envía el FORMULARIO, que es ancestro del modal, y
  # su `turbo:submit-end` no le llegaba. Con un sync vivo el aviso quedaba
  # debajo del modal abierto (19ª auditoría).
  test "en la genérica, si la conversión no procede por un sync, el modal se cierra" do
    estimate = estimate!
    sign_in @user
    visit conversion_order_path(estimate, client_key: "UIC01")
    SyncRun.create!(kind: "down", status: "running", pid: Process.pid, started_at: Time.current)

    click_button "Convertir en pedido"
    within("[role=dialog]") { click_button "Sí, convertir" }

    assert_text "Se está actualizando la información"
    assert_no_selector "[role=dialog]", visible: true
    assert Order.exists?(estimate.id)
  end

  # La de cliente pasaba por un modal; la genérica convertía de un toque.
  test "la genérica pide confirmar antes de convertir" do
    estimate = estimate!
    sign_in @user
    visit conversion_order_path(estimate, client_key: "UIC01")

    click_button "Convertir en pedido"
    within("[role=dialog]") do
      assert_text "ya guardado: se enviará al ERP en la siguiente transmisión"
      click_button "Cancelar"
    end
    assert Order.exists?(estimate.id), "abrir el modal no convierte"

    click_button "Convertir en pedido"
    within("[role=dialog]") { click_button "Sí, convertir" }

    assert_text "se convirtió en el pedido"
    assert_not Order.exists?(estimate.id)
  end
end
