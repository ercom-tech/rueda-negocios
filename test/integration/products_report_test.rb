require "test_helper"

# Reporte de productos: piezas vendidas por producto en la rueda.
class ProductsReportTest < ActionDispatch::IntegrationTest
  setup do
    @round    = BusinessRound.create!(erp_round_id: 9701, name: "Rueda PR", active: true)
    Setting.instance.update!(selected_round_erp_id: 9701, selected_round_name: "Rueda PR")

    @supplier = Supplier.create!(erp_supplier_id: 9701, name: "MAKITA")
    @other    = Supplier.create!(erp_supplier_id: 9702, name: "FANDELI")
    @brand    = Brand.create!(erp_brand_id: 9701, name: "MARCA UNO")

    @user  = User.create!(erp_person_id: 9701, username: "cap_pr", password: "secret123",
                          role: "capturista", active: true)
    @mate  = User.create!(erp_person_id: 9702, username: "cap_pr2", password: "secret123",
                          role: "capturista", active: true)
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @supplier, position: 1)
    BusinessRoundPerson.create!(business_round: @round, user: @user, brand: @brand, position: 2)
    BusinessRoundPerson.create!(business_round: @round, user: @mate, supplier: @other, position: 1)

    @client = Client.create!(erp_client_key: "PR01", name: "Cliente PR")

    @martillo = product!(9711, "MARTILLO DEMOLEDOR", model: "HM1810", part: "P-100", supplier: @supplier, sku: "MK-001")
    @lija     = product!(9712, "LIJA OXIDO", model: "X-86", part: "P-200", supplier: @other, sku: "FN-001")
    @generico = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "FUERA DE CATALOGO")
    Price.create!(product: @generico, credit_wholesale_price: 1, tax_rate: 16)
  end

  def product!(erp_id, description, model:, part:, supplier:, sku:)
    p = Product.create!(erp_product_id: erp_id, description: description, model: model,
                        part_number: part, max_discount: 50)
    Price.create!(product: p, credit_wholesale_price: 100, tax_rate: 16)
    ProductSupplier.create!(product: p, supplier: supplier, supplier_sku: sku)
    p
  end

  def order!(user: @user, status: "captured", folio: nil)
    Order.create!(user: user, business_round: @round, client: @client, kind: "remission",
                  status: status, local_folio: folio || "RN-#{format('%06d', rand(1_000_000))}")
  end

  def item!(order, product, quantity:, gift: false, description: nil, part_number: nil)
    item = order.order_items.new(product: product, position: order.order_items.count + 1,
                                 quantity: quantity, unit_price: 100, discount_percent: 0,
                                 tax_rate: 16, code: product.erp_code,
                                 description: description || product.description,
                                 part_number: part_number, unit: "PZA")
    item.gift = gift
    item.save!(validate: false)
    item
  end

  # --- La cantidad ---------------------------------------------------------

  test "suma las piezas de todos los pedidos del usuario" do
    item!(order!, @martillo, quantity: 3)
    item!(order!, @martillo, quantity: 2)
    login_as "cap_pr"

    get products_report_path

    assert_response :success
    rows = ProductSales.new(@user.orders).catalog_rows
    assert_equal 5, rows.find { |r| r.code == "009711" }.sold
  end

  # Vendido y regalado en columnas separadas: las dos son piezas que salen del
  # almacén, pero mezclarlas escondería cuánto se bonificó.
  test "los regalos van en su propia columna, no sumados a la cantidad" do
    order = order!
    item!(order, @martillo, quantity: 4)
    item!(order, @martillo, quantity: 2, gift: true)

    row = ProductSales.new(@user.orders).catalog_rows.first

    assert_equal 4, row.sold
    assert_equal 2, row.gifted
  end

  # Un borrador no es venta, y además cambia mientras se captura: contarlo
  # haría que el reporte se moviera solo entre dos consultas.
  test "los borradores no cuentan" do
    item!(order!(status: "draft"), @martillo, quantity: 9)
    item!(order!(status: "captured"), @martillo, quantity: 1)

    assert_equal 1, ProductSales.new(@user.orders).catalog_rows.first.sold
  end

  test "los transmitidos sí cuentan" do
    order = order!(status: "captured")
    item!(order, @martillo, quantity: 7)
    order.update!(status: "transmitted", erp_folio: "1A0001", transmitted_at: Time.current)

    assert_equal 7, ProductSales.new(@user.orders).catalog_rows.first.sold
  end

  # --- Alcance por rol -----------------------------------------------------

  test "un capturista no ve las piezas de pedidos ajenos" do
    item!(order!(user: @user), @martillo, quantity: 2)
    item!(order!(user: @mate), @lija, quantity: 50)

    rows = ProductSales.new(@user.orders).catalog_rows

    assert_equal [ "009711" ], rows.map(&:code)
  end

  # --- Filtros -------------------------------------------------------------

  test "el filtro de proveedor acota" do
    item!(order!, @martillo, quantity: 2)
    item!(order!, @lija, quantity: 5)
    todos = Order.all

    assert_equal [ "009711" ], ProductSales.new(todos, supplier_id: @supplier.id).catalog_rows.map(&:code)
    assert_equal [ "009712" ], ProductSales.new(todos, supplier_id: @other.id).catalog_rows.map(&:code)
  end

  test "el filtro de marca acota" do
    @lija.update!(brand: @brand)
    item!(order!, @martillo, quantity: 2)
    item!(order!, @lija, quantity: 5)

    assert_equal [ "009712" ], ProductSales.new(Order.all, brand_id: @brand.id).catalog_rows.map(&:code)
  end

  # Los combos ofrecen solo el universo del capturista; un id tecleado en la
  # URL no puede saltarse eso.
  test "un supplier_id fuera del universo del capturista se ignora" do
    item!(order!, @martillo, quantity: 2)
    login_as "cap_pr"

    get products_report_path(supplier_id: @other.id)

    assert_response :success
    # Se ignora el filtro ajeno: se ve el reporte completo, no uno vacío que
    # haría creer que no vendió nada.
    assert_match(/MARTILLO DEMOLEDOR/, response.body)
  end

  # --- Fuera de catálogo ---------------------------------------------------

  # El genérico es UN product_id con muchas descripciones: agruparlo por
  # producto sumaría peras con manzanas.
  test "el genérico se agrupa por lo que se tecleó, no por producto" do
    order = order!
    item!(order, @generico, quantity: 2, description: "TALADRO RARO", part_number: "T-1")
    item!(order, @generico, quantity: 3, description: "TALADRO RARO", part_number: "T-1")
    item!(order, @generico, quantity: 1, description: "OTRA COSA", part_number: "O-9")

    rows = ProductSales.new(@user.orders).generic_rows

    assert_equal 2, rows.size
    assert_equal 5, rows.find { |r| r.description == "TALADRO RARO" }.sold
    assert_equal 1, rows.find { |r| r.description == "OTRA COSA" }.sold
  end

  test "el genérico no aparece en la tabla de catálogo" do
    item!(order!, @generico, quantity: 4, description: "ALGO")
    item!(order!, @martillo, quantity: 1)

    sales = ProductSales.new(@user.orders)

    assert_equal [ "009711" ], sales.catalog_rows.map(&:code)
    assert_equal 1, sales.generic_rows.size
  end

  # Con un filtro activo el genérico no pertenece a ese proveedor, así que no
  # se muestra — pero se anuncia, o el reporte filtrado se lee como "esto fue
  # todo lo que se vendió".
  test "con filtro, el genérico se esconde pero se avisa" do
    item!(order!, @generico, quantity: 6, description: "ALGO")
    item!(order!, @martillo, quantity: 1)

    sales = ProductSales.new(Order.all, supplier_id: @supplier.id)

    assert_empty sales.generic_rows
    assert_equal 6, sales.hidden_generic_quantity
  end

  test "sin filtro no hay nada que avisar" do
    item!(order!, @generico, quantity: 6, description: "ALGO")

    assert_equal 0, ProductSales.new(Order.all).hidden_generic_quantity
  end

  # --- Exportación ---------------------------------------------------------

  test "el CSV trae encabezados, BOM y los renglones" do
    item!(order!, @martillo, quantity: 3)
    item!(order!, @generico, quantity: 2, description: "ALGO FUERA")
    login_as "cap_pr"

    get products_report_path(format: :csv)

    assert_response :success
    assert_match %r{text/csv}, response.media_type + response.headers["Content-Type"].to_s
    # El BOM es lo que hace que Excel en Windows respete los acentos.
    assert response.body.start_with?("﻿"), "el CSV debe empezar con BOM UTF-8"
    assert_match(/Código FECEGO;?,?/, response.body)
    assert_match(/MARTILLO DEMOLEDOR/, response.body)
    assert_match(/MK-001/, response.body)
    # El fuera de catálogo también va en el archivo.
    assert_match(/ALGO FUERA/, response.body)
  end

  # El archivo se abre en Excel para trabajarlo: si saliera paginado como la
  # pantalla, faltarían renglones sin que nada lo dijera.
  test "el CSV va completo aunque la pantalla pagine" do
    30.times { |i| item!(order!, product!(9800 + i, "PRODUCTO #{i}", model: "M", part: "P", supplier: @supplier, sku: "S#{i}"), quantity: 1) }
    login_as "cap_pr"

    get products_report_path(format: :csv, per_page: 25)

    filas = response.body.lines.size - 1 # sin el encabezado
    assert_operator filas, :>=, 30, "el CSV no debe recortarse al tamaño de página"
  end

  test "el Excel se descarga con su tipo y trae los datos" do
    item!(order!, @martillo, quantity: 3)
    item!(order!, @generico, quantity: 2, description: "ALGO FUERA")
    login_as "cap_pr"

    get products_report_path(format: :xlsx)

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                 response.media_type
    assert_match(/productos.*\.xlsx/, response.headers["Content-Disposition"])
    # Un .xlsx es un ZIP: los primeros bytes lo delatan, y es lo que distingue
    # un archivo que Excel abre de uno que solo se llama .xlsx.
    assert response.body.start_with?("PK"), "el .xlsx debe ser un contenedor ZIP válido"
    assert_operator response.body.bytesize, :>, 1_000
  end

  # Dos cosas que solo se ven abriendo el XML de la hoja, y las dos importan:
  # la cantidad tiene que ser NÚMERO (si no, Excel no la suma sin convertirla)
  # y el código FECEGO tiene que conservar sus ceros a la izquierda — caxlsx
  # adivina el tipo y guardaba "009711" como el número 9711.
  test "el Excel guarda cantidades como número y códigos como texto" do
    item!(order!, @martillo, quantity: 7)
    login_as "cap_pr"

    get products_report_path(format: :xlsx)

    sheet = nil
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.xlsx")
      File.binwrite(path, response.body)
      sheet = `unzip -p #{path} xl/worksheets/sheet1.xml 2>/dev/null`
    end
    skip "unzip no disponible" if sheet.to_s.empty?

    assert_match(/t="n"><v>7\.?0?<\/v>/, sheet, "la cantidad debe ir como número")
    assert_match(/009711/, sheet, "el código debe conservar los ceros a la izquierda")
    assert_no_match(/<v>9711<\/v>/, sheet, "el código NO debe guardarse como número")
  end

  # --- Pantalla ------------------------------------------------------------

  test "la card del hub ya no dice Próximamente" do
    login_as "cap_pr"

    get reports_path

    assert_response :success
    assert_match(/Reporte de<br>productos|Reporte de.*productos/m, response.body)
    assert_select "a[href=?]", products_report_path
  end

  test "la pantalla muestra las columnas pedidas" do
    item!(order!, @martillo, quantity: 3)
    login_as "cap_pr"

    get products_report_path

    assert_response :success
    %w[Código Descripción Modelo Cantidad Regalos].each { |h| assert_match(/#{h}/, response.body) }
    assert_match(/No\. de parte/, response.body)
    assert_match(/SKU proveedor/, response.body)
    assert_match(/009711/, response.body)
    assert_match(/MK-001/, response.body)
  end

  test "la pantalla ofrece las dos descargas" do
    item!(order!, @martillo, quantity: 3)
    login_as "cap_pr"

    get products_report_path

    assert_select "a[href=?]", products_report_path(format: :csv)
    assert_select "a[href=?]", products_report_path(format: :xlsx)
  end

  # La descarga se lleva los filtros de la pantalla: un archivo con TODO
  # mientras se ve MAKITA sería una sorpresa al abrirlo.
  test "las descargas conservan el filtro activo" do
    item!(order!, @martillo, quantity: 3)
    item!(order!, @lija, quantity: 5)
    login_as "cap_pr"

    get products_report_path(format: :csv, supplier_id: @supplier.id)

    assert_match(/MARTILLO DEMOLEDOR/, response.body)
    assert_no_match(/LIJA OXIDO/, response.body)
  end
end
