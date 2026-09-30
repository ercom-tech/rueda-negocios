require "test_helper"

# Cuándo aparece el botón "Producto nuevo" junto al buscador.
#
# Solo cuando el 999999 bajó en condiciones de capturarse (con precio y tasa
# de IVA): es el MISMO criterio con el que el panel avisa que falta
# (`Product.capturable_generic`). Si el botón usara otro, el panel diría que
# nadie puede capturar fuera de catálogo mientras el botón lo ofrece — y la
# partida nacería con IVA 0%, porque sin precio la tasa cae a cero.
class NewProductButtonVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 970_411, username: "cap_btn_vis", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_411, name: "Rueda visibilidad", active: true)
    Setting.instance.update!(selected_round_erp_id: 970_411, selected_round_name: "Rueda visibilidad")
    @client = Client.create!(erp_client_key: "VIS01", name: "Cliente")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
  end

  def generic!(with_price: true)
    product = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "AJUSTE DE MERCANCIA", unit: "PZA")
    Price.create!(product: product, credit_wholesale_price: 0, tax_rate: 16) if with_price
    product
  end

  test "con el 999999 capturable, el botón aparece y apunta al genérico" do
    generic = generic!
    login_as "cap_btn_vis"

    get order_path(@order)

    assert_select "form[action=?] button", order_order_items_path(@order, product_id: generic.id),
                  text: /Producto nuevo/
  end

  test "sin el 999999 el botón no aparece" do
    login_as "cap_btn_vis"

    get order_path(@order)

    assert_response :success
    assert_no_match(/Producto nuevo/, response.body)
  end

  test "con el 999999 sin precio el botón no aparece" do
    generic!(with_price: false)
    login_as "cap_btn_vis"

    get order_path(@order)

    assert_no_match(/Producto nuevo/, response.body)
  end

  # Con precio pero SIN tasa de IVA tampoco: la partida nacería con IVA 0%, y
  # el aviso del panel (`missing_generic`) usa el mismo criterio.
  test "con el 999999 sin tasa de IVA el botón no aparece" do
    product = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "AJUSTE", unit: "PZA")
    Price.create!(product: product, credit_wholesale_price: 0, tax_rate: nil)
    login_as "cap_btn_vis"

    get order_path(@order)

    assert_no_match(/Producto nuevo/, response.body)
    assert_not Product.capturable_generic.exists?
  end

  # La barra de totales muestra el TOTAL (con IVA), no el subtotal otra vez:
  # la prueba de sistema usa IVA 0 y no podía distinguirlos (12ª auditoría).
  test "la barra de totales muestra el total con IVA" do
    @order.order_items.create!(position: 1, quantity: 1, unit_price: 100, tax_rate: 16, discount_percent: 0,
                               code: "000001", description: "MARTILLO", unit: "PZA")
    login_as "cap_btn_vis"

    get order_path(@order)
    bar = response.body[/<span id="order-totals-bar-content".*?<\/span>\s*<\/span>\s*<\/span>/m]

    assert_match(/Subtotal <span class="tabular-nums">\$100\.00/, bar)
    assert_match(/Total <span class="tabular-nums">\$116\.00/, bar)
  end

  # Mismo alcance que el buscador: solo el dueño, mientras se puede editar.
  test "en un pedido ajeno el botón no aparece" do
    generic!
    User.create!(erp_person_id: 970_412, username: "srv_btn_vis", password: "secret123",
                 role: "server", active: true)
    login_as "srv_btn_vis"

    get order_path(@order)

    assert_response :success
    assert_no_match(/Producto nuevo/, response.body)
  end

  test "en un pedido transmitido el botón no aparece" do
    generic!
    @order.update_columns(status: "transmitted", local_folio: "RN-000411", erp_folio: "1A0411")
    login_as "cap_btn_vis"

    get order_path(@order)

    assert_no_match(/Producto nuevo/, response.body)
  end

  # "Cotizador": pantalla por definir (2026-09-29). Mientras tanto se ve
  # deshabilitado —un botón activo que no hace nada se leería como falla— y
  # sin "Próximamente", como lo pidió el usuario. Cuando tenga función, esta
  # prueba se reemplaza.
  test "el botón Cotizador aparece deshabilitado y sin próximamente" do
    login_as "cap_btn_vis"

    get order_path(@order)

    assert_select "button[disabled][aria-disabled=true]", text: /Cotizador/
    assert_no_match(/Próximamente/, response.body)
  end

  # No depende del 999999: se ve aunque "Producto nuevo" no esté.
  test "el Cotizador se ve aunque no haya producto nuevo" do
    login_as "cap_btn_vis"

    get order_path(@order)

    assert_no_match(/Producto nuevo/, response.body)
    assert_match(/Cotizador/, response.body)
  end
end
