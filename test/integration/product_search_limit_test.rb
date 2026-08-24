require "test_helper"

# El tope del buscador y su aviso. Era 10 y silencioso: sobre el catálogo real
# de la rueda, "LIJA" da 256 coincidencias y "TORNILLO" 228, así que 9 de cada
# 10 búsquedas por palabra completa se cortaban sin decirlo — y "no está" se
# veía igual que "quedó en el puesto 11".
class ProductSearchLimitTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 9501, username: "cap_bus", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 9501, name: "Rueda BUS", active: true)
    Setting.instance.update!(selected_round_erp_id: 9501, selected_round_name: "Rueda BUS")
    @supplier = Supplier.create!(erp_supplier_id: 9501, name: "PROVEEDOR")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @supplier, position: 1)
    client = Client.create!(erp_client_key: "BUS1", name: "Cliente BUS")
    @order = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")
    login_as "cap_bus"
  end

  def make_products(count, prefix)
    count.times do |i|
      p = Product.create!(erp_product_id: 500_000 + i, description: "#{prefix} MODELO #{i}",
                          unit: "PZA", max_discount: 5)
      Price.create!(product: p, credit_wholesale_price: 100, tax_rate: 16)
      ProductSupplier.create!(product: p, supplier: @supplier)
    end
  end

  test "el buscador devuelve hasta el tope" do
    make_products(60, "LIJA")

    get product_options_order_path(@order), params: { q: "LIJA" }

    assert_equal Product::SEARCH_LIMIT, response.body.scan(/<li>/).size
  end

  # El resto de las pruebas se escribe contra la constante —así siguen valiendo
  # si el número cambia— pero el VALOR también es una decisión con datos
  # detrás: sobre el catálogo de la rueda, "LIJA" da 256 coincidencias,
  # "TORNILLO" 228 y "LLAVE" 178. Un tope de 10 dejaba fuera 9 de cada 10
  # búsquedas por palabra completa; bajarlo otra vez a ese orden reabre el
  # problema sin que ninguna otra prueba se entere.
  test "el tope es holgado, no una decena" do
    assert_operator Product::SEARCH_LIMIT, :>=, 25
    assert_equal Product::SEARCH_LIMIT, Client::SEARCH_LIMIT,
                 "los dos buscadores se recorren igual; que no diverjan en silencio"
  end

  # Sin el aviso, el capturista no sabe si refinar la búsqueda o capturar el
  # producto fuera de catálogo.
  test "cuando hay más coincidencias que el tope, se dice" do
    make_products(60, "LIJA")

    get product_options_order_path(@order), params: { q: "LIJA" }

    assert_match(/Se muestran las primeras #{Product::SEARCH_LIMIT} coincidencias/, response.body)
    assert_match(/escribe más letras/, response.body)
  end

  test "sin corte no aparece el aviso" do
    make_products(3, "LIJA")

    get product_options_order_path(@order), params: { q: "LIJA" }

    assert_equal 3, response.body.scan(/<li>/).size
    assert_no_match(/Se muestran las primeras/, response.body)
  end

  # Justo en el tope tampoco: pedir uno de más es cómo se detecta el corte, y
  # el de más no debe contarse como resultado ni disparar el aviso.
  test "exactamente en el tope no se avisa ni se muestra de más" do
    make_products(Product::SEARCH_LIMIT, "LIJA")

    get product_options_order_path(@order), params: { q: "LIJA" }

    assert_equal Product::SEARCH_LIMIT, response.body.scan(/<li>/).size
    assert_no_match(/Se muestran las primeras/, response.body)
  end
end
