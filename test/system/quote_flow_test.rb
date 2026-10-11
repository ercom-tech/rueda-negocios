require "application_system_test_case"

# El Cotizador en navegador real: qué partida está seleccionada. Todo esto
# vive en `quote_controller` —la selección, su realce y el nombre del botón se
# reaplican tras cada morph—, y la integración no lo puede ver (14ª
# auditoría).
class QuoteFlowTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_401, username: "cap_quote_sys", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_401, name: "Rueda cotizador", active: true)
    Setting.instance.update!(selected_round_erp_id: 970_401, selected_round_name: "Rueda cotizador")
    client   = Client.create!(erp_client_key: "SYS05", name: "Cliente cotizador")
    @supplier = Supplier.create!(erp_supplier_id: 970_401, name: "MAKITA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @supplier, position: 1)

    @taladro = product("TALADRO", 1000)
    @esmeril = product("ESMERIL", 500)
    @order   = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")
    promo = Promotion.create!(erp_promotion_id: 970_401, code: "MAKR20", name: "MAKITA - OAXACA",
                              starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    promo.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CM", unit: "MXN",
                                  quantity_from: 1000, quantity_to: 0, discount_percent: 14)
    [ @taladro, @esmeril ].each { |p| promo.promotion_products.create!(product: p, discount_percent: 0) }
  end

  def product(description, price)
    item = Product.create!(erp_product_id: rand(1_000_000..9_999_999), description: description,
                           unit: "PZA", max_discount: 9)
    Price.create!(product: item, credit_wholesale_price: price, tax_rate: 16)
    ProductSupplier.create!(product: item, supplier: @supplier)
    item
  end

  def add_item(product)
    @order.order_items.create!(product.to_order_item_attributes.merge(
      position: @order.next_item_position, quantity: 1, discount_percent: 0
    ))
  end

  def selected_row_id = find("#order-detail tr[aria-current=true]")[:id]
  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

  def quote_and_assert(text)
    click_button "Cotizador"
    within("#quote-dialog") { assert_text text }
    within("#quote-dialog") { click_button "Cerrar" }
  end

  test "al abrir el pedido está seleccionada la partida más reciente" do
    add_item(@taladro)
    esmeril = add_item(@esmeril)
    sign_in @user
    visit order_path(@order)

    assert_equal dom_id(esmeril), selected_row_id
    assert_equal "Cotizar ESMERIL", find("[data-quote-target=button]")["aria-label"]
    quote_and_assert "ESMERIL"
  end

  test "tocar otra fila la selecciona" do
    taladro = add_item(@taladro)
    add_item(@esmeril)
    sign_in @user
    visit order_path(@order)

    find("##{dom_id(taladro)} td:nth-child(3)").click

    assert_equal dom_id(taladro), selected_row_id
    quote_and_assert "TALADRO"
  end

  # El alta no le da el foco a la fila nueva: sin esto, agregar y cotizar
  # cotizaba la partida de antes.
  test "al agregar un producto, su fila queda seleccionada" do
    taladro = add_item(@taladro)
    sign_in @user
    visit order_path(@order)
    find("##{dom_id(taladro)} td:nth-child(3)").click

    fill_in "Busca por código, nombre, modelo o No. de parte", with: "ESMERIL"
    click_button "ESMERIL", match: :first
    assert_selector "#order-detail tbody tr", count: 2, wait: 5

    new_row = dom_id(@order.order_items.order(:position).last)
    assert_selector "##{new_row}[aria-current=true]"
    quote_and_assert "ESMERIL"
  end

  # El morph regresa los atributos al HTML del servidor, que no sabe qué fila
  # está seleccionada.
  test "la selección sobrevive al repintado de una cantidad" do
    taladro = add_item(@taladro)
    esmeril = add_item(@esmeril)
    sign_in @user
    visit order_path(@order)

    fill_in "quantity_order_item_#{taladro.id}", with: "3"
    find("##{dom_id(esmeril)} td:nth-child(3)").click # blur → guardar → morph
    find("##{dom_id(taladro)} td:nth-child(3)").click
    assert_selector "##{dom_id(taladro)}", text: "$3,480.00" # total con IVA

    assert_equal dom_id(taladro), selected_row_id
    assert_equal "Cotizar TALADRO", find("[data-quote-target=button]")["aria-label"]
    # Forma además de color: la barra negra de la primera celda.
    assert_match(/4px 0px 0px inset/, evaluate_script("document.querySelector('##{dom_id(taladro)} td').style.boxShadow"))
  end

  test "al quitar la seleccionada, la toma la más reciente" do
    taladro = add_item(@taladro)
    esmeril = add_item(@esmeril)
    sign_in @user
    visit order_path(@order)
    assert_equal dom_id(esmeril), selected_row_id

    find("##{dom_id(esmeril)} button[aria-label^='Quitar producto']").click
    within("##{ActionView::RecordIdentifier.dom_id(esmeril, :remove_dialog)}") { click_button "Sí, quitar" }

    assert_selector "##{dom_id(taladro)}[aria-current=true]", wait: 5
  end

  test "sin partidas, el Cotizador dice qué hacer" do
    sign_in @user
    visit order_path(@order)

    click_button "Cotizador"

    within("#quote-dialog") { assert_text "todavía no tiene productos para cotizar" }
  end
end
