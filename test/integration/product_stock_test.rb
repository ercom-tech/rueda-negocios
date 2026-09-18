require "test_helper"

# La existencia en el buscador de producto, a la derecha del precio.
#
# Es de MATRIZ —de donde la rueda surte y factura— y viene de la última
# obtención de información: una referencia para decidir si ofrecer el producto,
# no una promesa de que estará al surtir.
class ProductStockTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 972_001, username: "cap_stock", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 972_001, name: "Rueda 972", active: true)
    Setting.instance.update!(selected_round_erp_id: 972_001, selected_round_name: "Rueda 972")
    @sup    = Supplier.create!(erp_supplier_id: 972_001, name: "PROVEEDOR")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @sup, position: 1)
    @client = Client.create!(erp_client_key: "STK01", name: "Cliente")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    login_as "cap_stock"
  end

  def product!(description, stock:, erp_id: 972_101)
    product = Product.create!(erp_product_id: erp_id, description: description, max_discount: 50,
                              stock: stock, unit: "PZA")
    Price.create!(product: product, credit_wholesale_price: 429.44, tax_rate: 16)
    ProductSupplier.create!(product: product, supplier: @sup)
    product
  end

  test "el buscador muestra la existencia junto al precio" do
    product!("MARTILLO CON EXISTENCIA", stock: 120)

    get product_options_order_path(@order, q: "MARTILLO")

    assert_response :success
    assert_match(/Existencia 120/, response.body)
    assert_match(/\$429\.44.*Existencia 120/m, response.body, "va a la DERECHA del precio")
  end

  # Lo accionable: el capturista puede ofrecer otra cosa ANTES de agregarlo.
  test "sin existencia lo dice con palabras, no con un cero" do
    product!("MARTILLO AGOTADO", stock: 0)

    get product_options_order_path(@order, q: "AGOTADO")

    assert_match(/Sin existencia/, response.body)
    assert_no_match(/Existencia 0/, response.body)
  end

  # El ERP puede traer existencias negativas (ajustes de inventario); para el
  # capturista significan lo mismo que cero.
  test "una existencia negativa se lee como sin existencia" do
    product!("MARTILLO NEGATIVO", stock: -5)

    get product_options_order_path(@order, q: "NEGATIVO")

    assert_match(/Sin existencia/, response.body)
    # Acotado a la etiqueta: un `/-5/` suelto casa con las clases CSS (`px-5`).
    assert_no_match(/Existencia -5/, response.body)
  end

  # Decimales: el catálogo es decimal(14,2) porque hay producto a granel, pero
  # "120.00" en una lista se lee como ruido.
  test "la existencia entera se muestra sin decimales, y la fraccionaria con ellos" do
    product!("CABLE GRANEL", stock: 12.5, erp_id: 972_102)

    get product_options_order_path(@order, q: "GRANEL")

    assert_match(/Existencia 12\.5/, response.body)
    assert_no_match(/12\.50/, response.body)
  end

  # El genérico no existe en el catálogo del ERP: no tiene precio NI existencia,
  # y prometerle una sería inventar.
  test "el genérico no muestra existencia" do
    generic = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "FUERA DE CATALOGO",
                              stock: 0, unit: "PZA")
    Price.create!(product: generic, credit_wholesale_price: 0, tax_rate: 16)

    get product_options_order_path(@order, q: "999999")

    assert_response :success
    assert_match(/Fuera de catálogo/, response.body)
    assert_no_match(/Sin existencia/, response.body)
    assert_no_match(/Existencia/, response.body)
  end
end
