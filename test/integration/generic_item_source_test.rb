require "test_helper"

# Proveedor y Marca del producto nuevo (genérico 999999), 2026-09-29.
#
# El capturista indica, entre sus proveedores y marcas asignados en la rueda, a
# quién pertenece lo que capturó fuera de catálogo: dos campos, obligatorio al
# menos uno. Con una sola asignación en total ya sale elegida. No va al pedido
# del ERP —no tiene dónde guardarlo— pero sí a su evidencia, y sirve a los dos
# reportes del evento, que antes escondían el genérico en cuanto se filtraba
# por proveedor o marca.
class GenericItemSourceTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    @round = BusinessRound.create!(erp_round_id: 966_101, name: "Rueda origen", active: true)
    Setting.instance.update!(selected_round_erp_id: 966_101, selected_round_name: "Rueda origen")
    @makita  = Supplier.create!(erp_supplier_id: 966_101, name: "MAKITA")
    @fandeli = Supplier.create!(erp_supplier_id: 966_102, name: "FANDELI")
    @hitools = Brand.create!(erp_brand_id: 966_101, name: "HITOOLS")
    @client  = Client.create!(erp_client_key: "ORI01", name: "Cliente")
    @generic = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "AJUSTE DE MERCANCIA", unit: "PZA")
    Price.create!(product: @generic, credit_wholesale_price: 0, tax_rate: 16)
  end

  def capturista!(username, *assignments)
    user = User.create!(erp_person_id: 966_100 + User.count + 1, username: username, password: "secret123",
                        role: "capturista", active: true)
    assignments.each_with_index do |record, index|
      key = record.is_a?(Supplier) ? :supplier : :brand
      BusinessRoundPerson.create!(business_round: @round, user: user, position: index + 1, key => record)
    end
    user
  end

  def order_of(user)
    Order.create!(user: user, business_round: @round, client: @client, kind: "remission")
  end

  def open_form(order)
    post order_order_items_path(order), params: { product_id: @generic.id }, headers: STREAM
  end

  def add_generic(order, supplier: nil, brand: nil, description: "CESPOL DE HULE")
    post order_order_items_path(order),
         params: { product_id: @generic.id,
                   generic: { description: description, part_number: "", unit_price: "50",
                              supplier_id: supplier, brand_id: brand }.compact },
         headers: STREAM
  end

  def hidden_value(name)
    response.body[/<input[^>]*name="#{Regexp.escape(name)}"[^>]*>/].to_s[/value="([^"]*)"/, 1]
  end

  # --- La ventanita -----------------------------------------------------------

  test "con una sola asignación ya sale elegida y el otro campo no aparece" do
    user = capturista!("cap_uno", @makita)
    login_as "cap_uno"

    open_form(order_of(user))

    assert_equal @makita.id.to_s, hidden_value("generic[supplier_id]")
    assert_no_match(/generic\[brand_id\]/, response.body, "sin marcas asignadas, no hay campo de marca")
  end

  # Un proveedor y una marca: dos asignaciones, así que nada sale elegido. Si
  # cada campo se eligiera solo por tener una opción, la partida quedaría
  # atribuida a los dos sin que el capturista lo decidiera.
  test "con proveedor y marca salen los dos campos, vacíos" do
    user = capturista!("cap_ambos", @makita, @hitools)
    login_as "cap_ambos"

    open_form(order_of(user))

    assert_predicate hidden_value("generic[supplier_id]"), :blank?
    assert_predicate hidden_value("generic[brand_id]"), :blank?
    assert_match(/Elige al menos uno de los dos/, response.body)
  end

  test "sin asignaciones no aparece ningún campo y no se exige" do
    user = capturista!("cap_nadie")
    login_as "cap_nadie"
    order = order_of(user)

    open_form(order)
    assert_no_match(/generic\[(supplier|brand)_id\]/, response.body)

    add_generic(order)
    item = order.order_items.sole
    assert_nil item.supplier_id
    assert_nil item.brand_id
  end

  # Nombre comercial y orden alfabético: con 24 proveedores, la razón social en
  # el orden de asignación del ERP no dejaba encontrar nada.
  test "los proveedores salen por nombre comercial y en orden alfabético" do
    @makita.update!(commercial_name: "ZETA")
    @fandeli.update!(commercial_name: "ALFA")
    user = capturista!("cap_orden", @makita, @fandeli)
    login_as "cap_orden"

    open_form(order_of(user))

    labels = response.body.scan(/role="option"[^>]*data-label="([^"]+)"/).flatten
    assert_equal [ "— Selecciona —", "ALFA", "ZETA" ], labels
    assert_not_includes labels, "MAKITA", "la razón social no se muestra si hay nombre comercial"
  end

  # --- La validación --------------------------------------------------------

  test "sin elegir ninguno de los dos no se agrega" do
    user = capturista!("cap_sin_elegir", @makita, @hitools)
    login_as "cap_sin_elegir"
    order = order_of(user)

    assert_no_difference "OrderItem.count" do
      add_generic(order)
    end
    assert_match(/Selecciona el proveedor o la marca del producto\./, response.body)
    # La ventanita vuelve con lo tecleado, para no reescribirlo.
    assert_match(/value="CESPOL DE HULE"/, response.body)
  end

  test "basta con el proveedor, basta con la marca, y se pueden los dos" do
    user = capturista!("cap_elige", @makita, @hitools)
    login_as "cap_elige"
    order = order_of(user)

    add_generic(order, supplier: @makita.id, description: "UNO")
    add_generic(order, brand: @hitools.id, description: "DOS")
    add_generic(order, supplier: @makita.id, brand: @hitools.id, description: "TRES")

    uno, dos, tres = order.order_items.order(:position).to_a
    assert_equal [ @makita.id, nil ], [ uno.supplier_id, uno.brand_id ]
    assert_equal [ nil, @hitools.id ], [ dos.supplier_id, dos.brand_id ]
    assert_equal [ @makita.id, @hitools.id ], [ tres.supplier_id, tres.brand_id ]
  end

  # "Lo que el combo ofrece, el modelo lo valida": el valor viaja en un campo
  # oculto, y un POST forjado podría traer el proveedor de otro capturista.
  test "un proveedor que no es de sus asignaciones se rechaza" do
    user = capturista!("cap_forja", @makita, @hitools)
    login_as "cap_forja"

    assert_no_difference "OrderItem.count" do
      add_generic(order_of(user), supplier: @fandeli.id, brand: @hitools.id)
    end
    assert_match(/El proveedor no está entre tus asignaciones/, response.body)
  end

  # Lo mismo con la marca: la de proveedor ya tenía prueba y la de marca no.
  test "una marca que no es de sus asignaciones se rechaza" do
    user = capturista!("cap_forja_marca", @makita, @hitools)
    otra = Brand.create!(erp_brand_id: 966_199, name: "AJENA")
    login_as "cap_forja_marca"

    assert_no_difference "OrderItem.count" do
      add_generic(order_of(user), brand: otra.id)
    end
    assert_match(/La marca no está entre tus asignaciones/, response.body)
  end

  # Un valor que no es un id no se ignora en silencio: dejaría pasar la partida
  # sin el dato que se pidió.
  test "un valor que no se entiende se rechaza sin error del sistema" do
    user = capturista!("cap_basura", @makita, @hitools)
    login_as "cap_basura"

    assert_no_difference "OrderItem.count" do
      add_generic(order_of(user), supplier: "abc")
    end
    assert_response :success
    assert_match(/El proveedor no está entre tus asignaciones/, response.body)
  end

  # Las partidas capturadas antes del campo no lo tienen: editar su
  # descripción en la fila no debe exigirles algo que nadie les pidió.
  test "una partida vieja sin proveedor se sigue pudiendo editar" do
    user = capturista!("cap_vieja", @makita, @hitools)
    order = order_of(user)
    item = order.order_items.new(product: @generic, position: 1, quantity: 1, unit_price: 50, tax_rate: 16,
                                 discount_percent: 0, code: "999999", description: "VIEJA", unit: "PZA")
    item.save!(validate: false)
    login_as "cap_vieja"

    patch order_order_item_path(order, item), params: { order_item: { description: "VIEJA CORREGIDA" } },
                                              headers: STREAM

    assert_equal "VIEJA CORREGIDA", item.reload.description
  end

  # --- La fila --------------------------------------------------------------

  test "la fila dice de quién es el producto nuevo" do
    @makita.update!(commercial_name: "MAKITA")
    user = capturista!("cap_fila", @makita, @hitools)
    order = order_of(user)
    login_as "cap_fila"
    add_generic(order, supplier: @makita.id, brand: @hitools.id)

    get order_path(order)

    assert_select "#order_item_#{order.order_items.sole.id}", text: /Proveedor: MAKITA · Marca: HITOOLS/
  end

  # --- Los reportes ---------------------------------------------------------

  def tagged_order(user, description:, supplier: nil, brand: nil, status: "captured")
    order = Order.create!(user: user, business_round: @round, client: @client, kind: "remission",
                          status: status, local_folio: "RN-#{format('%06d', rand(1_000_000))}")
    item = order.order_items.new(product: @generic, position: 1, quantity: 3, unit_price: 100, tax_rate: 0,
                                 discount_percent: 0, code: "999999", description: description, unit: "PZA",
                                 supplier_id: supplier&.id, brand_id: brand&.id)
    item.save!(validate: false)
    order
  end

  test "el reporte de productos muestra el producto nuevo bajo su proveedor" do
    user = capturista!("cap_rep", @makita, @fandeli)
    tagged_order(user, supplier: @makita, description: "DE MAKITA")
    tagged_order(user, supplier: @fandeli, description: "DE FANDELI")
    tagged_order(user, description: "SIN NADIE")
    login_as "cap_rep"

    get products_report_path(supplier_id: @makita.id)

    assert_match(/DE MAKITA/, response.body)
    assert_no_match(/DE FANDELI/, response.body)
    assert_no_match(/SIN NADIE/, response.body)
    # Las otras 6 piezas se anuncian, no desaparecen.
    assert_match(/Además se capturaron\s*<span class="font-semibold">6<\/span>/, response.body)
  end

  test "el reporte de pedidos encuentra el pedido por el proveedor del producto nuevo" do
    user = capturista!("cap_ped", @makita, @fandeli)
    mine  = tagged_order(user, supplier: @makita, description: "DE MAKITA")
    other = tagged_order(user, supplier: @fandeli, description: "DE FANDELI")
    login_as "cap_ped"

    get captured_orders_report_path(supplier_id: @makita.id)

    assert_match(/#{mine.local_folio}/, response.body)
    assert_no_match(/#{other.local_folio}/, response.body)
    # El importe de la tarjeta es el de la partida que coincide: 3 × $100.
    filter = OrdersFilter.new(supplier_id: @makita.id)
    summary = filter.apply_without_status(Order.all).totals_by_status(filter.matching_items_sql)
    assert_in_delta 300, summary["captured"][:total], 0.01
    assert_equal 1, summary["captured"][:count]
  end

  # Una partida con proveedor Y marca aparece filtrando por cualquiera de los
  # dos, y con los dos filtros juntos solo si tiene ambos.
  test "con proveedor y marca, la partida aparece por cualquiera de los dos" do
    user = capturista!("cap_dos", @makita, @hitools)
    both = tagged_order(user, supplier: @makita, brand: @hitools, description: "DE LOS DOS")
    only = tagged_order(user, supplier: @makita, description: "SOLO MAKITA")
    login_as "cap_dos"

    get captured_orders_report_path(brand_id: @hitools.id)
    assert_match(/#{both.local_folio}/, response.body)
    assert_no_match(/#{only.local_folio}/, response.body)

    get captured_orders_report_path(supplier_id: @makita.id, brand_id: @hitools.id)
    assert_match(/#{both.local_folio}/, response.body)
    assert_no_match(/#{only.local_folio}/, response.body)

    get products_report_path(brand_id: @hitools.id)
    assert_match(/DE LOS DOS/, response.body)
    assert_no_match(/SOLO MAKITA/, response.body)
  end

  # Agregar un filtro no puede ENSANCHAR el resultado: "cespol" solo no
  # hallaba el producto nuevo "CESPOL DE HULE" y "cespol" + su proveedor sí.
  # Y "999999" + proveedor no hallaba lo que "999999" solo sí (12ª auditoría).
  test "el filtro de texto encuentra al producto nuevo con o sin proveedor" do
    user = capturista!("cap_mono", @makita)
    cespol = tagged_order(user, supplier: @makita, description: "CESPOL DE HULE")
    login_as "cap_mono"

    [ { product_q: "cespol" }, { product_q: "cespol", supplier_id: @makita.id },
      { product_q: "999999" }, { product_q: "999999", supplier_id: @makita.id } ].each do |filter|
      get captured_orders_report_path(filter)
      assert_match(/#{cespol.local_folio}/, response.body, filter.inspect)
    end
  end

  # Un id que no cabe en un bigint no revienta el reporte: da "sin
  # resultados", como antes de la condición por partida.
  test "un id enorme en la URL del reporte no da error" do
    capturista!("cap_enorme", @makita)
    login_as "cap_enorme"

    get captured_orders_report_path(supplier_id: "99999999999999999999")

    assert_response :success
  end

  # El mensaje nombra solo los campos que el capturista tiene en pantalla.
  test "el mensaje pide solo el campo que se muestra" do
    solo_proveedores = capturista!("cap_solo_prov", @makita, @fandeli)
    login_as "cap_solo_prov"
    add_generic(order_of(solo_proveedores))
    assert_match(/Selecciona el proveedor del producto\./, response.body)

    solo_marcas = capturista!("cap_solo_marca", @hitools, Brand.create!(erp_brand_id: 966_102, name: "ARATY"))
    login_as "cap_solo_marca"
    add_generic(order_of(solo_marcas))
    assert_match(/Selecciona la marca del producto\./, response.body)
  end

  # Con texto de producto, en el genérico se busca lo que el capturista tecleó.
  test "el texto del filtro busca en la descripción capturada del producto nuevo" do
    user = capturista!("cap_txt", @makita)
    cespol = tagged_order(user, supplier: @makita, description: "CESPOL DE HULE")
    taladro = tagged_order(user, supplier: @makita, description: "TALADRO")
    login_as "cap_txt"

    get captured_orders_report_path(supplier_id: @makita.id, product_q: "cespol")

    assert_match(/#{cespol.local_folio}/, response.body)
    assert_no_match(/#{taladro.local_folio}/, response.body)
  end
end
