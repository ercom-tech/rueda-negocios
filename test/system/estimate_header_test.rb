require "application_system_test_case"

# El paso 1 de la cotización y el aviso de partida quitada, en navegador real
# (16ª auditoría): capas, confirmación y foco solo se ven con clics.
class EstimateHeaderTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_701, username: "cap_head", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_701, name: "Rueda head", active: true)
    Setting.instance.update!(selected_round_erp_id: 970_701, selected_round_name: "Rueda head")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1,
                                supplier: Supplier.create!(erp_supplier_id: 970_701, name: "PROV"))
    @client = Client.create!(erp_client_key: "HEAD01", name: "CLIENTE HEAD")
    @client.receipt_profiles.create!(name: "REMISION")
  end

  def estimate_with_client
    Order.create!(user: @user, business_round: @round, document: "estimate", client: @client,
                  kind: "remission", client_receipt_profile: @client.receipt_profiles.first)
  end

  # Con z-20 en el header y z-10 en el contenido, el modal quedaba DEBAJO de
  # la barra superior y "Cerrar sesión" respondía con él abierto.
  test "el modal de Cliente genérico tapa la barra superior" do
    sign_in @user
    visit edit_order_path(estimate_with_client)

    click_button "Cliente genérico"
    assert_button "Sí, cambiar"

    on_top = evaluate_script(<<~JS)
      (() => {
        const b = [...document.querySelectorAll("button")].find(x => x.textContent.trim() === "Cerrar sesión")
        const r = b.getBoundingClientRect()
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
        return hit.closest("[data-modal-target=dialog]") ? "modal" : hit.textContent.trim()
      })()
    JS
    assert_equal "modal", on_top
  end

  # Ya elegido un cliente, un toque en "Cliente genérico" lo tiraba sin
  # preguntar: ahora confirma, como al editar.
  test "en una cotización nueva con cliente elegido, Cliente genérico pide confirmación" do
    sign_in @user
    visit new_order_path(client_key: "HEAD01", document: "estimate")

    assert_no_difference("Order.estimate.count") { click_button "Cliente genérico" }
    assert_text "Se quitará el cliente elegido"

    click_button "Sí, cambiar"
    assert_text "Cotización iniciada"
    assert Order.estimate.last.generic?
  end

  test "la partida quitada en otra pestaña devuelve el foco al buscador" do
    estimate = estimate_with_client
    2.times do |i|
      estimate.order_items.create!(position: i + 1, quantity: 1, unit_price: 100, tax_rate: 16,
                                   discount_percent: 0, description: "PIEZA #{i + 1}", unit: "PZA")
    end
    gone = estimate.order_items.find_by(position: 1)
    sign_in @user
    visit order_path(estimate)

    OrderItem.where(id: gone.id).delete_all
    find("button[aria-label='Quitar producto — PIEZA 1']").click
    click_button "Sí, quitar"

    assert_text "Esa partida ya no está en la cotización"
    assert_equal "product-search", evaluate_script("document.activeElement.closest('#product-search')?.id")
  end
end
