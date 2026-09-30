require "application_system_test_case"

# La barra fija de totales en la pantalla de captura.
#
# Pedido del evento: con muchas partidas, para ver los totales había que bajar
# hasta el final. La barra aparece SOLO cuando la tarjeta de totales no se ve
# completa, para no repetir los importes cuando hay pocas partidas. Todo eso
# vive entre Stimulus, IntersectionObserver y el morph de Turbo: una prueba de
# integración no lo puede ver.
class TotalsBarTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_301, username: "cap_bar", password: "secret123",
                          role: "capturista", active: true)
    round  = BusinessRound.create!(erp_round_id: 970_301, name: "Rueda barra", active: true)
    @supplier = Supplier.create!(erp_supplier_id: 970_301, name: "PROVEEDOR BARRA")
    BusinessRoundPerson.create!(business_round: round, user: @user, position: 1, supplier: @supplier)
    client = Client.create!(erp_client_key: "BAR01", name: "Cliente barra")
    @order = Order.create!(user: @user, business_round: round, client: client, kind: "remission")
  end

  def items!(count)
    count.times do |index|
      position = index + 1
      @order.order_items.create!(position: position, quantity: 1, unit_price: 100, tax_rate: 0,
                                 discount_percent: 0, code: "97#{position.to_s.rjust(4, '0')}",
                                 description: "PRODUCTO #{position}", unit: "PZA")
    end
  end

  def bar
    find("[data-totals-bar-target=bar]", visible: :all)
  end

  test "con muchas partidas la barra aparece arriba con los totales" do
    items!(40)
    sign_in @user
    visit order_path(@order)

    assert bar.visible?, "con 40 partidas la tarjeta de totales queda fuera de la pantalla"
    within(bar) do
      assert_text "40 partidas"
      assert_text "Subtotal $4,000.00"
      assert_text "Total $4,000.00"
    end
  end

  # Píldora al ancho de su contenido y centrada (decisión del usuario
  # 2026-09-29): a todo lo ancho tapaba de orilla a orilla los renglones que
  # se están leyendo.
  test "la barra es una píldora centrada, no una franja de lado a lado" do
    items!(40)
    sign_in @user
    visit order_path(@order)
    assert bar.visible?

    box = evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector("[data-totals-bar-target=bar] button").getBoundingClientRect()
        return { left: r.left, right: r.right, width: r.width, viewport: window.innerWidth }
      })()
    JS

    assert_operator box["width"], :<, box["viewport"] * 0.6, "no ocupa todo el ancho"
    assert_in_delta box["left"], box["viewport"] - box["right"], 2, "queda centrada"
  end

  # Las orillas del contenedor quedan vacías pero siguen encima de la tabla:
  # si recibieran los toques, la partida de abajo no se podría tocar.
  test "junto a la barra se puede tocar lo que queda debajo" do
    items!(40)
    sign_in @user
    visit order_path(@order)
    assert bar.visible?

    under = evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector("[data-totals-bar-target=bar] button").getBoundingClientRect()
        const el = document.elementFromPoint(20, r.top + r.height / 2)
        return el.closest("[data-totals-bar-target=bar]") ? "barra" : "página"
      })()
    JS

    assert_equal "página", under
  end

  # Nunca los importes dos veces: al llegar a la tarjeta, la barra se va.
  test "al bajar hasta la tarjeta de totales la barra se esconde" do
    items!(40)
    sign_in @user
    visit order_path(@order)
    assert bar.visible?

    execute_script("window.scrollTo(0, document.body.scrollHeight)")

    assert_selector "[data-totals-bar-target=bar]", visible: :hidden
  end

  test "tocar la barra lleva a la tarjeta completa" do
    items!(40)
    sign_in @user
    visit order_path(@order)

    bar.click

    assert_selector "[data-totals-bar-target=bar]", visible: :hidden
    assert_selector "#order-totals", text: "IVA"
  end

  # La cifra de la barra tiene que seguir a la captura: si se quedara con el
  # total de cuando se abrió la pantalla, le cantaría al cliente una cifra
  # vieja. Se repinta con el mismo stream que la tarjeta.
  test "la barra se actualiza al corregir una cantidad" do
    items!(40)
    sign_in @user
    visit order_path(@order)
    newest = @order.order_items.order(:position).last

    fill_in "quantity_order_item_#{newest.id}", with: "5"
    find("h1", text: "Levantamiento de pedido").click # blur: dispara el auto-guardado

    within(bar) { assert_text "Subtotal $4,400.00" }
  end

  # El caso que motivó la objeción del usuario: con pocas partidas la tarjeta
  # ya se ve y repetir los importes sobraría. La ventana se hace alta para que
  # la pantalla entera quepa sin bajar.
  test "con pocas partidas la barra no aparece" do
    items!(2)
    page.driver.browser.manage.window.resize_to(1400, 2000)
    sign_in @user
    visit order_path(@order)

    assert_selector "#order-totals", text: "Total"
    assert_selector "[data-totals-bar-target=bar]", visible: :hidden
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # ¿Lo que está en el centro de este elemento es el elemento mismo, o algo que
  # lo tapa (la barra)?
  def uncovered?(css)
    evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector(#{css.to_json})
        const r = el.getBoundingClientRect()
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
        return hit === el || el.contains(hit)
      })()
    JS
  end

  # En tablet horizontal, la partida recién agregada quedaba pegada al borde
  # de abajo —justo donde flota la barra— y la barra le tapaba la Cantidad, el
  # campo que el capturista corrige enseguida. Pasaba en CADA alta (12ª
  # auditoría).
  test "la partida recién agregada no queda debajo de la barra" do
    items!(30)
    product = Product.create!(erp_product_id: 970_399, description: "BISAGRA DE LIBRO", unit: "PZA", max_discount: 0)
    Price.create!(product: product, credit_wholesale_price: 50, tax_rate: 16)
    ProductSupplier.create!(product: product, supplier: @supplier)
    # Ventana de 1024×700: la zona visible queda en ~560 px, la de una tablet
    # horizontal menos la barra del navegador. Con más de ~600 el renglón
    # nuevo ya no cae bajo la barra y la prueba no vería el defecto.
    page.driver.browser.manage.window.resize_to(1024, 700)
    sign_in @user
    visit order_path(@order)
    assert bar.visible?

    fill_in "Busca por código, nombre, modelo o No. de parte", with: "BISAGRA"
    click_button "BISAGRA DE LIBRO", match: :first
    assert_selector "tbody tr", count: 31

    new_item = @order.order_items.order(:position).last
    sleep 0.6 # el scroll suave del renglón nuevo
    assert uncovered?("#quantity_order_item_#{new_item.id}"), "la barra tapa la Cantidad del renglón nuevo"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # Al tocar la barra, la página baja y la barra se oculta con el foco
  # adentro: el foco caía al <body> y el siguiente Tab empezaba desde arriba.
  test "después de tocar la barra el foco queda en la tarjeta de totales" do
    items!(40)
    sign_in @user
    visit order_path(@order)

    bar.click
    assert_selector "[data-totals-bar-target=bar]", visible: :hidden

    assert_equal "order-totals", evaluate_script("document.activeElement.id")
  end
end
