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
    find("#order_item_#{item.id} button[aria-label='Quitar producto']")
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
    assert_text "¿Quitar \"LLAVE PERICO 10\" del pedido?"
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
end
