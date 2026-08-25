require "test_helper"

# El tope de los buscadores y su aviso. Era 10 y silencioso: sobre el catálogo
# real de la rueda, "LIJA" da 256 coincidencias, "TORNILLO" 228 y "LLAVE" 178,
# así que el corte era la regla y no la excepción — y "no está" se veía igual
# que "quedó en el puesto 11".
#
# El recorte de esa afirmación, que antes faltaba: contando productos distintos
# por palabra de 4+ letras de `products.description`, el 90% de las 1,000
# palabras MÁS FRECUENTES rebasa 10 coincidencias; sobre las 12,166 palabras
# distintas del catálogo (la mayoría casi nunca tecleadas) es el 7.4%. Lo que
# importa es lo primero: se teclea lo frecuente (8ª auditoría).
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

  # --- El buscador de CLIENTE, que no tenía ninguna prueba ------------------
  # El controlador calculaba el corte en una ivar y el partial lo lee de los
  # locals, así que el aviso no se pintaba NUNCA: quedó como código muerto que
  # nada delataba —ninguna prueba tocaba esta ruta— mientras el buscador de
  # producto, con el mismo texto, sí funcionaba (8ª auditoría).
  def make_clients(count)
    count.times { |i| Client.create!(erp_client_key: "FER#{i.to_s.rjust(3, '0')}", name: "FERRETERIA #{i}") }
  end

  test "el buscador de cliente devuelve hasta el tope" do
    make_clients(60)

    get client_options_orders_path, params: { q: "FERRETERIA" }

    assert_equal Client::SEARCH_LIMIT, response.body.scan(/<li>/).size
  end

  test "cuando hay más clientes que el tope, se dice" do
    make_clients(60)

    get client_options_orders_path, params: { q: "FERRETERIA" }

    assert_match(/Se muestran las primeras #{Client::SEARCH_LIMIT} coincidencias/, response.body)
    assert_match(/escribe más letras/, response.body)
  end

  test "sin corte no aparece el aviso de clientes" do
    make_clients(3)

    get client_options_orders_path, params: { q: "FERRETERIA" }

    assert_equal 3, response.body.scan(/<li>/).size
    assert_no_match(/Se muestran las primeras/, response.body)
  end

  # El aviso no puede colgar del listbox: ese role solo admite option/group.
  test "el aviso de corte queda fuera del listbox" do
    make_clients(60)

    get client_options_orders_path, params: { q: "FERRETERIA" }

    # El <ul> es el listbox y cierra ANTES del aviso.
    listbox_end = response.body.index("</ul>")
    aviso       = response.body.index("Se muestran las primeras")
    assert listbox_end && aviso, "deben existir el listbox y el aviso"
    assert_operator listbox_end, :<, aviso, "el aviso quedó dentro del listbox"
    assert_match(/<ul[^>]*role="listbox"/, response.body)
  end
end
