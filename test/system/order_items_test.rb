require "application_system_test_case"

# La pantalla de captura, en un navegador de verdad.
#
# Es el flujo que más duele si se rompe y el que concentra el JavaScript hecho
# a mano del proyecto. Los defectos que vive aquí no se ven desde una prueba de
# integración: nacen de la interacción entre Turbo (morph), idiomorph y
# Stimulus, no de la respuesta del servidor.
class OrderItemsTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_001, username: "cap_sys", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_001, name: "Rueda sistema", active: true)
    supplier = Supplier.create!(erp_supplier_id: 970_001, name: "PROVEEDOR SISTEMA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: supplier)
    client = Client.create!(erp_client_key: "SYS01", name: "Cliente sistema")

    @order = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")
    @first  = item!("MARTILLO DE UÑA", 1)
    @second = item!("LLAVE PERICO 10", 2)
  end

  def item!(description, position)
    @order.order_items.create!(position: position, quantity: 1, unit_price: 100,
                               tax_rate: 0, discount_percent: 0,
                               code: "9700#{position}", description: description, unit: "PZA")
  end

  def trash_button_of(item)
    # Por prefijo: el aria-label completo nombra la partida ("Quitar producto
    # — MARTILLO..."), para que las filas no se anuncien todas igual.
    find("#order_item_#{item.id} button[aria-label^='Quitar producto']")
  end

  # El defecto: el diálogo se abre poniendo un `style` en línea, y el
  # auto-guardado de la cantidad dispara en `blur` un PATCH que repinta
  # `#order-detail` con morph. Idiomorph reescribe ese `style` con el
  # `display:none` del HTML nuevo y el modal recién abierto desaparece solo.
  #
  # En captura seguida es la pareja de acciones más común: corregir una
  # cantidad y quitar la partida que sobra. Se ve como "el bote de basura no
  # hace nada", y con eventos sintéticos NO se reproduce.
  test "el modal de quitar sobrevive al repintado que dispara editar una cantidad" do
    sign_in @user
    visit order_path(@order)

    fill_in "quantity_order_item_#{@first.id}", with: "5"
    trash_button_of(@second).click

    assert_selector "[role=dialog]", visible: true

    # Espera a que el repintado llegue de verdad: el total de la fila editada
    # pasa de $100.00 a $500.00. Sin esta espera la prueba pasaría siempre,
    # porque estaría comprobando el modal antes de que el morph ocurra.
    assert_selector "#order_item_#{@first.id}", text: "$500.00"

    assert_selector "[role=dialog]", visible: true, wait: 0
    # El mensaje nombra la partida: con el mismo producto repetido, la
    # descripción sola no dice cuál de las dos se va a quitar.
    assert_text "¿Quitar la partida 2, \"LLAVE PERICO 10\", del pedido?"
  end

  # Sin edición previa no hay repintado, así que el modal se queda abierto: es
  # el caso que sí funcionaba y que hacía ver el defecto como intermitente.
  test "el modal de quitar se abre y permite cancelar" do
    sign_in @user
    visit order_path(@order)

    trash_button_of(@second).click
    assert_selector "[role=dialog]", visible: true

    click_button "Cancelar"
    assert_no_selector "[role=dialog]", visible: true
    assert_equal 2, @order.order_items.count
  end

  test "confirmar quita la partida y renumera el consecutivo" do
    sign_in @user
    visit order_path(@order)

    trash_button_of(@first).click
    click_button "Sí, quitar"

    assert_no_selector "#order_item_#{@first.id}"
    assert_equal [ 1 ], @order.order_items.reload.map(&:position)
  end

  # --- Orden de la tabla (2026-09-02) --------------------------------------
  # La más reciente arriba. Es cambio de VISTA, pero la tabla se repinta con
  # morph, así que hay que verlo en navegador: idiomorph empareja por id y
  # tiene que MOVER la fila nueva al principio, no recrear la tabla — si la
  # recreara, el foco y el estado de los campos se perderían en cada alta.
  test "una partida agregada por el buscador aparece arriba, sin recrear la tabla" do
    supplier = Supplier.find_by(erp_supplier_id: 970_001)
    nuevo = Product.create!(erp_product_id: 970_003, description: "TALADRO NUEVO", max_discount: 50)
    Price.create!(product: nuevo, credit_wholesale_price: 500, tax_rate: 0)
    ProductSupplier.create!(product: nuevo, supplier: supplier)

    sign_in @user
    visit order_path(@order)

    # Marca en un nodo existente: si idiomorph recreara la tabla en vez de
    # mover la fila nueva al principio, la marca desaparecería — y con ella el
    # foco y lo tecleado en cualquier campo a medio editar.
    #
    # Propiedad JS y NO `dataset`: un data-attr es un ATRIBUTO, e idiomorph
    # sincroniza los atributos con los del HTML nuevo, así que lo borraría
    # aunque el nodo fuera el mismo. Una propiedad expando solo desaparece si
    # el elemento se reemplaza de verdad.
    page.execute_script(<<~JS)
      document.querySelector("input[aria-label='Cantidad — MARTILLO DE UÑA']").__marca = "viva"
    JS

    fill_in "Busca por código, nombre, modelo o No. de parte", with: "TALADRO"
    click_button "TALADRO NUEVO", match: :first

    # Esperar a la TABLA, no al texto: "TALADRO NUEVO" aparece también en el
    # buscador, así que `assert_text` se cumple antes de que el morph termine
    # de repintar y la lectura de abajo agarraba la tabla a medio camino.
    assert_selector "tbody tr", count: 3, wait: 5

    # Por el CONSECUTIVO y no por la descripción: en una partida con producto
    # la descripción vive en un input, y el `.text` de un input es vacío.
    assert_equal %w[3 2 1], all("tbody tr td:nth-child(2)").map(&:text),
                 "la más reciente arriba"

    fila_nueva = @order.order_items.order(:position).last
    assert_equal ActionView::RecordIdentifier.dom_id(fila_nueva), all("tbody tr").first[:id],
                 "la primera fila es la partida recién agregada"

    marca = page.evaluate_script(
      "document.querySelector(\"input[aria-label='Cantidad — MARTILLO DE UÑA']\").__marca"
    )
    assert_equal "viva", marca, "idiomorph reusó los nodos existentes en vez de recrear la tabla"
  end

  # El bote de basura nombra la partida por su descripción, no por su lugar en
  # la tabla: invertir el orden no puede hacer que borre la equivocada.
  test "el bote de basura sigue apuntando a su propia partida" do
    sign_in @user
    visit order_path(@order)

    trash_button_of(@first).click
    within "##{ActionView::RecordIdentifier.dom_id(@first, :remove_dialog)}" do
      click_button "Sí, quitar"
    end

    assert_no_text "MARTILLO DE UÑA"
    assert_text "LLAVE PERICO 10", wait: 5
  end
end
