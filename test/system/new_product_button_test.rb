require "application_system_test_case"

# El botón "Producto nuevo", a la derecha del buscador: atajo a la ventanita
# del producto fuera de catálogo (999999), la misma que se abre eligiendo el
# 999999 en las sugerencias.
#
# Va en navegador real porque el camino cruza lo más frágil de la pantalla: el
# buscador limpia su panel al terminar CUALQUIER envío (turbo:submit-end), y el
# botón es un envío que tiene que dejar la ventanita abierta en ese mismo panel.
class NewProductButtonTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_401, username: "cap_new_btn", password: "secret123",
                          role: "capturista", active: true)
    round  = BusinessRound.create!(erp_round_id: 970_401, name: "Rueda botón", active: true)
    client = Client.create!(erp_client_key: "BTN01", name: "Cliente botón")
    @order = Order.create!(user: @user, business_round: round, client: client, kind: "remission")
    # Sin membresías: el genérico es de todos (decisión FECEGO 2026-08-17).
    generic = Product.create!(erp_product_id: Product::GENERIC_ERP_ID,
                              description: "AJUSTE DE MERCANCIA", unit: "PZA")
    Price.create!(product: generic, credit_wholesale_price: 0, tax_rate: 16)
  end

  test "el botón abre la ventanita con el foco en Descripción y agrega la partida" do
    sign_in @user
    visit order_path(@order)

    click_button "Producto nuevo"

    assert_text "Producto fuera de catálogo (999999)"
    assert_equal "generic_description", page.evaluate_script("document.activeElement.id"),
                 "el foco tiene que caer en Descripción, no quedarse en el botón"

    fill_in "Descripción", with: "CESPOL DE HULE"
    fill_in "Precio unitario", with: "226.94"
    click_button "Agregar al pedido"

    assert_text "Partidas: 1"
    item = @order.order_items.sole
    assert item.generic?
    assert_equal "CESPOL DE HULE", item.description
    assert_equal 16, item.tax_rate.to_i, "el IVA es el del 999999 del ERP"
  end

  test "Cancelar cierra la ventanita abierta desde el botón" do
    sign_in @user
    visit order_path(@order)

    click_button "Producto nuevo"
    assert_selector "#generic_description"

    click_button "Cancelar"

    assert_no_selector "#generic_description"
    assert_equal 0, @order.order_items.count
  end

  # Volver a tocar el botón con la ventanita a medio llenar: la respuesta la
  # reemplazaría por una vacía y se perdería lo tecleado. El botón solo
  # devuelve el foco al formulario.
  test "tocar el botón otra vez no borra lo que ya se tecleó" do
    sign_in @user
    visit order_path(@order)

    click_button "Producto nuevo"
    fill_in "Descripción", with: "TALADRO ESPECIAL"
    fill_in "Precio unitario", with: "150.50"

    click_button "Producto nuevo"

    assert_field "Descripción", with: "TALADRO ESPECIAL"
    assert_field "Precio unitario", with: "150.50"
    assert_equal "generic_description", page.evaluate_script("document.activeElement.id")
  end

  # La barra fija de totales (z-40) quedaba ENCIMA del panel del buscador:
  # en tablet con poca altura —el teclado en pantalla la quita— tapaba
  # "Cancelar" y "Agregar al pedido". El panel tiene que ganar.
  test "la barra de totales no tapa los botones de la ventanita" do
    30.times do |index|
      @order.order_items.create!(position: index + 1, quantity: 1, unit_price: 100, tax_rate: 0,
                                 discount_percent: 0, code: "98#{index.to_s.rjust(4, '0')}",
                                 description: "PRODUCTO #{index + 1}", unit: "PZA")
    end
    page.driver.browser.manage.window.resize_to(768, 700)
    sign_in @user
    visit order_path(@order)
    click_button "Producto nuevo"
    assert_selector "#generic_description"
    assert_selector "[data-totals-bar-target=bar]", visible: true
    execute_script("window.scrollTo(0, 250)")

    [ "Cancelar", "Agregar al pedido" ].each do |label|
      hit = evaluate_script(<<~JS)
        (() => {
          const target = [...document.querySelectorAll("#product-search-results button")]
            .find((b) => b.textContent.trim() === #{label.to_json})
          const r = target.getBoundingClientRect()
          return document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)?.closest("button") === target
        })()
      JS
      assert hit, "«#{label}» tiene que recibir el toque, no la barra de totales"
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # Buscar 999999 sigue siendo un camino: hay capturistas que ya lo conocen.
  test "el 999999 se sigue pudiendo elegir desde el buscador" do
    sign_in @user
    visit order_path(@order)

    fill_in "Busca por código, nombre, modelo o No. de parte", with: "999999"
    click_button "Capturar"

    assert_text "Producto fuera de catálogo (999999)"
  end
end
