require "application_system_test_case"

# Las promociones en navegador real. Aquí viven los defectos que la
# integración no puede ver: el modal es UNO por promoción con botones
# repartidos por toda la tabla (elección de diálogo por id), y toda la región
# se repinta con morph en cada cambio — que es lo que cerraba modales solos
# antes de `data-turbo-permanent`.
class PromotionFlowTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_301, username: "cap_promo_sys", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_301, name: "Rueda promo", active: true)
    Setting.instance.update!(selected_round_erp_id: 970_301, selected_round_name: "Rueda promo")
    client   = Client.create!(erp_client_key: "SYS04", name: "Cliente promo")
    supplier = Supplier.create!(erp_supplier_id: 970_301, name: "MAKITA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: supplier, position: 1)

    @taladro = product("TALADRO", 1000, supplier)
    @esmeril = product("ESMERIL", 500, supplier)
    @order   = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")

    @promo = Promotion.create!(erp_promotion_id: 970_301, code: "MAKR20", name: "MAKITA - OAXACA",
                               starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    @promo.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CM", unit: "MXN",
                                   quantity_from: 1000, quantity_to: 0, discount_percent: 14)
    [ @taladro, @esmeril ].each { |p| @promo.promotion_products.create!(product: p, discount_percent: 0) }

    add_item(@taladro, 2)
    add_item(@esmeril, 2)
  end

  def product(description, price, supplier)
    item = Product.create!(erp_product_id: rand(1_000_000..9_999_999), description: description,
                           unit: "PZA", max_discount: 9)
    Price.create!(product: item, credit_wholesale_price: price, tax_rate: 16)
    ProductSupplier.create!(product: item, supplier: supplier)
    item
  end

  def add_item(product, quantity)
    @order.order_items.create!(product.to_order_item_attributes.merge(
      position: @order.next_item_position, quantity: quantity, discount_percent: 0
    ))
  end

  # El botón de CADA fila tiene que abrir el diálogo de su promoción. Con un
  # solo `dialogTarget` el controller abría siempre el primero del contenedor
  # — que aquí es el de "quitar partida" de la fila 1.
  test "la flama de cualquier fila abre el modal de su promoción" do
    sign_in @user
    visit order_path(@order)

    all("[aria-label^='Promoción MAKITA']").last.click

    assert_selector "#promotion-dialog-#{@promo.id}", visible: true
    assert_text "MAKITA - OAXACA"
    assert_text "Llevas $3,000.00"
  end

  test "aplicar desde el modal descuenta las dos partidas y las bloquea" do
    sign_in @user
    visit order_path(@order)

    first("[aria-label^='Promoción MAKITA']").click
    click_button "Aplicar promoción"

    assert_text "Se aplicó la promoción"
    # Las dos partidas quedaron al 14% y sin campo editable: el input de
    # cantidad desaparece, no solo se deshabilita. Contado sobre las FILAS y
    # no sobre la página: el flash y el modal también dicen "14%", y la
    # prueba pasaría aunque las filas se hubieran quedado en cero.
    assert_selector "#order-detail tbody tr", count: 2
    assert_equal 2, all("#order-detail tbody tr").count { |row| row.text.include?("14%") }
    assert_no_selector "input[aria-label^='Cantidad']"
    assert_no_selector "input[aria-label^='Descuento']"
  end

  # El diálogo vive dentro de #order-detail, que se repinta con morph en cada
  # cambio. Sin `data-turbo-permanent` e id estable, idiomorph reescribe el
  # `style` en línea con el del HTML nuevo y el modal abierto se cierra solo.
  test "el modal abierto sobrevive a un repintado de la tabla" do
    sign_in @user
    visit order_path(@order)

    # Un cambio de cantidad dispara el repintado con morph de toda la región.
    # Se ancla a la partida por su nombre y no con `first`: la tabla muestra la
    # más reciente ARRIBA, así que "la primera fila" es el esmeril, y los
    # importes que se comprueban abajo son los del taladro.
    quantity = find("input[aria-label='Cantidad — TALADRO']")
    quantity.set("3")
    quantity.native.send_keys(:tab)
    assert_text "$3,480.00"   # ya repintó

    first("[aria-label^='Promoción MAKITA']").click
    assert_selector "#promotion-dialog-#{@promo.id}", visible: true

    # Con el modal ABIERTO, otro repintado. Tiene que CAMBIAR el valor:
    # `submitIfChanged` compara contra lo que recordó en el focus, así que un
    # focus/blur a secas no envía nada y la prueba pasaría sin que ningún
    # morph hubiera ocurrido.
    page.execute_script(<<~JS)
      const input = document.querySelector("input[aria-label='Descuento (%) — TALADRO']")
      input.dispatchEvent(new FocusEvent("focus"))
      input.value = "3"
      input.dispatchEvent(new FocusEvent("blur"))
    JS
    assert_text "$4,535.60"   # el total ya trae el 3%: el morph ocurrió

    assert_selector "#promotion-dialog-#{@promo.id}", visible: true
  end

  # --- El modal contra el layout y el foco (7ª auditoría) -------------------

  # El diálogo es `z-50`, pero si su wrapper lleva un z-index ese 50 solo
  # compite DENTRO de ese contexto de apilamiento: la barra superior se pintaba
  # encima del modal y un toque cerca de su borde caía en "Cerrar sesión".
  test "la barra superior no se pinta encima del modal" do
    sign_in @user
    visit order_path(@order)
    first("[aria-label^='Promoción MAKITA']").click
    assert_selector "#promotion-dialog-#{@promo.id}", visible: true

    # Sobre la barra de título del propio modal: quien recibe el punto tiene
    # que ser el diálogo, no el header.
    owner = page.evaluate_script(<<~JS)
      (function () {
        const dialog = document.querySelector("#promotion-dialog-#{@promo.id}")
        const card = dialog.querySelector(".relative")
        const r = card.getBoundingClientRect()
        const el = document.elementFromPoint(r.left + r.width / 2, r.top + 12)
        return el.closest("[data-modal-target='dialog']") ? "modal" : el.tagName
      })()
    JS
    assert_equal "modal", owner, "la barra superior se está pintando encima del modal"

    # Y el fondo oscuro cierra en toda su área, no solo por debajo del header.
    assert page.evaluate_script(<<~JS), "el fondo no recibe el clic cerca del borde superior"
      (function () {
        const el = document.elementFromPoint(window.innerWidth / 2, 20)
        return !!el.closest("#promotion-dialog-#{@promo.id}")
      })()
    JS
  end

  # `focusables()[0]` corría cuando el turbo-frame solo tenía el placeholder,
  # que no tiene ninguno: el foco se quedaba fuera para siempre y el focus-trap
  # no atrapaba nada (comparaba contra el primero y el último del diálogo, y el
  # activo no era ninguno). Tres tabuladores llegaban a los inputs de la tabla,
  # detrás del overlay, y una tecla editaba una partida a ciegas.
  #
  # Lo que de verdad cierra el hueco es que "Cerrar" viva en el CASCARÓN: el
  # diálogo tiene un enfocable desde el primer instante, aunque el frame no
  # haya cargado. `modal#focusInside` (reintento en `turbo:frame-load`) y el
  # trap endurecido son redundancia para el día que ese botón se mueva.
  test "el foco entra al diálogo y no se escapa con Tab" do
    sign_in @user
    visit order_path(@order)
    first("[aria-label^='Promoción MAKITA']").click
    assert_text "Aplicar promoción"   # el contenido ya llegó

    assert page.evaluate_script("!!document.activeElement.closest(\"#promotion-dialog-#{@promo.id}\")"),
           "el foco quedó fuera del diálogo"

    # Tres tabuladores no deben sacar el foco a los controles de la tabla, que
    # están detrás del overlay: ahí una tecla editaba una partida a ciegas.
    3.times { page.driver.browser.action.send_keys(:tab).perform }
    assert page.evaluate_script("!!document.activeElement.closest(\"#promotion-dialog-#{@promo.id}\")"),
           "Tab escapó del modal: el foco aterrizó en #{page.evaluate_script('document.activeElement.getAttribute("aria-label") || document.activeElement.tagName')}"
  end

  # Si la carga del contenido falla, el diálogo se quedaba a pantalla completa
  # sin un solo control: el botón Cerrar vivía dentro del frame que no cargó.
  test "el botón Cerrar existe aunque el contenido no haya cargado" do
    sign_in @user
    visit order_path(@order)

    # Se mira el cascarón ANTES de abrirlo: el frame es lazy y no ha pedido nada.
    assert_selector "#promotion-dialog-#{@promo.id} button", text: "Cerrar", visible: :all
  end

  test "quitar la promoción devuelve las partidas a manos del capturista" do
    sign_in @user
    visit order_path(@order)
    first("[aria-label^='Promoción MAKITA']").click
    click_button "Aplicar promoción"
    assert_text "Se aplicó la promoción"

    first("[aria-label^='Promoción MAKITA']").click
    click_button "Quitar promoción"

    assert_text "vuelven a ser editables"
    assert_selector "input[aria-label^='Cantidad']", count: 2
  end
end
