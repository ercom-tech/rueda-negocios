require "application_system_test_case"

# El producto fuera de catálogo (999999) en navegador real: elegirlo en el
# buscador abre el mini-formulario (no agrega directo), y su fila queda
# editable en descripción, parte y precio con el mismo auto-guardado que la
# cantidad. Todo vive entre Turbo (morph) y Stimulus — la integración no ve
# los defectos de ese cruce.
class GenericItemFlowTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_201, username: "cap_gen_sys", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_201, name: "Rueda genérico", active: true)
    client = Client.create!(erp_client_key: "SYS03", name: "Cliente genérico")
    @order = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")
    # Sin membresías a propósito: el genérico es de todos (decisión FECEGO).
    Product.create!(erp_product_id: Product::GENERIC_ERP_ID,
                    description: "AJUSTE DE MERCANCIA", unit: "PZA")
  end

  # Las rutas de pérdida que la 6ª auditoría confirmó con clics reales: clic
  # fuera, teclear con el foco fantasma en el buscador. Con captura a medias
  # el panel queda protegido; solo Cancelar descarta.
  test "el mini-formulario no se pierde por rutas implícitas y Cancelar sí lo cierra" do
    sign_in @user
    visit order_path(@order)

    fill_in "Busca por código, nombre, modelo o No. de parte", with: "999999"
    click_button "Capturar"

    # El foco aterriza en Descripción (connect del controller), no en el
    # buscador — antes, la primera tecla caía al buscador y destruía el
    # formulario.
    assert_selector "#generic_description"
    assert_equal "generic_description", page.evaluate_script("document.activeElement.id")

    fill_in "Descripción", with: "TALADRO ESPECIAL"
    fill_in "Precio unitario", with: "150.50"

    # Clic fuera: el panel NO se limpia.
    find("body").click
    assert_field "Descripción", with: "TALADRO ESPECIAL"

    # Teclear en el buscador tampoco lo destruye.
    find("[aria-label='Buscar producto']").click
    find("[aria-label='Buscar producto']").send_keys("t")
    assert_field "Descripción", with: "TALADRO ESPECIAL"

    # Cancelar sí lo descarta, a propósito, y devuelve el foco al buscador.
    click_button "Cancelar"
    assert_no_selector "#generic_description"
    assert_equal 0, @order.order_items.count
  end

  test "capturar y editar un producto fuera de catálogo de punta a punta" do
    sign_in @user
    visit order_path(@order)

    # Elegirlo NO agrega: abre el mini-formulario en el panel del buscador.
    fill_in "Busca por código, nombre, modelo o No. de parte", with: "999999"
    click_button "Capturar"
    assert_text "Producto fuera de catálogo"

    fill_in "Descripción", with: "CESPOL DE HULE"
    fill_in "No. de parte (opcional)", with: "ABC-1"
    fill_in "Precio unitario", with: "226.94"
    click_button "Agregar al pedido"

    # La descripción vive en un input (la fila del genérico es editable), así
    # que se afirma por campo, no por texto visible.
    assert_text "Partidas 1 / 45"
    item = @order.order_items.sole
    assert_field "description_order_item_#{item.id}", with: "CESPOL DE HULE"
    assert_equal 226.94, item.unit_price

    # La fila es editable en sitio: cambiar la descripción y salir guarda.
    fill_in "description_order_item_#{item.id}", with: "CESPOL DE LATON"
    find("body").click # blur → submitIfChanged

    # El PATCH viaja en el blur: esperar a que aterrice en la BD.
    10.times do
      break if item.reload.description == "CESPOL DE LATON"

      sleep 0.2
    end
    assert_equal "CESPOL DE LATON", item.reload.description
  end
end
