require "test_helper"

# Cambiar precios desde el panel del servidor: subir → revisar → aplicar, y
# quitar. Las reglas de lectura y comparación viven en test/services/price_list.
class PricesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @server = User.create!(erp_person_id: 974_001, username: "srv_po", password: "secret123", role: "server", active: true)
    @round  = BusinessRound.create!(erp_round_id: 974_001, name: "Rueda 974", active: true)
    Setting.instance.update!(selected_round_erp_id: 974_001, selected_round_name: "Rueda 974")
    @saw    = product(974_101, "MOTOSIERRA", 6500)
    @blower = product(974_102, "SOPLADORA", 1000)
    @dir = Dir.mktmpdir
    login_as "srv_po"
  end

  teardown do
    FileUtils.remove_entry(@dir)
    FileUtils.rm_rf(PriceList::Upload::ROOT)
  end

  def product(code, description, price)
    Product.create!(erp_product_id: code, description: description).tap do |p|
      Price.create!(product: p, credit_wholesale_price: price, tax_rate: 16)
    end
  end

  def upload(text, name: "stihl.csv")
    path = File.join(@dir, name).tap { |p| File.write(p, text) }
    Rack::Test::UploadedFile.new(path, "text/csv", original_filename: name)
  end

  def review!(text = "CODIGO,PRECIO LISTA S/IVA\n974101,6900\n974102,1000\n999,5\n", **)
    post server_prices_review_path, params: { file: upload(text, **) }
    assert_response :redirect
    token = response.location[%r{/review/(\h+)\z}, 1]
    assert token, "debe llevar a la revisión, llevó a #{response.location}"
    token
  end

  test "revisar muestra qué cambiaría sin escribir nada" do
    token = review!
    get server_price_review_path(token)

    assert_response :success
    assert_match(/Todavía no se ha cambiado nada/, response.body)
    assert_match(/Aplicar 1 cambio\b/, response.body)
    assert_match(/stihl\.csv/, response.body)
    assert_equal 0, PriceOverride.count
  end

  # El segundo renglón de cada tarjeta es un dato, como el importe del reporte.
  test "las tarjetas dicen hacia dónde se mueven los precios y por qué no se aplican" do
    token = review!("CODIGO,PRECIO LISTA S/IVA\n974101,6900\n974102,900\n999,5\n3021,\n")

    get server_price_review_path(token)
    assert_select "a", text: /Cambian\s+2\s+1 sube · 1 baja/
    assert_select "a", text: /No se aplican\s+2\s+1 fuera de la rueda · 1 sin precio/
    assert_select "a", text: /Quedan igual\s+0\s+Mismo precio que hoy/
  end

  # Las tarjetas son el filtro, como en el reporte de pedidos: por omisión la
  # tabla trae lo que se aplica; cada tarjeta la cambia a su grupo.
  test "las tarjetas filtran la tabla al grupo elegido" do
    token = review!

    get server_price_review_path(token)
    assert_select "a[aria-current=true]", text: /Cambian/
    assert_select "tbody tr", count: 1
    assert_select "tbody td", text: "MOTOSIERRA"

    get server_price_review_path(token, group: "rejected")
    assert_select "a[aria-current=true]", text: /No se aplican/
    assert_select "thead th", text: "Motivo"
    assert_select "tbody td", text: "No está en el catálogo de esta rueda."
    assert_select "tbody td", text: "MOTOSIERRA", count: 0

    get server_price_review_path(token, group: "unchanged")
    assert_select "tbody td", text: "SOPLADORA"

    get server_price_review_path(token, group: "large")
    assert_select "tbody td", text: /Ningún renglón del archivo cae en este grupo/

    get server_price_review_path(token, group: "inventado")
    assert_select "a[aria-current=true]", text: /Cambian/
  end

  # El umbral solo decide qué se SEÑALA, y viaja en tarjetas, paginador y CSV
  # para no regresar al de omisión al moverse.
  test "el umbral de variación se elige y se conserva" do
    token = review!("CODIGO,PRECIO LISTA S/IVA\n974101,7800\n974102,1100\n") # +20% y +10%

    get server_price_review_path(token)
    assert_select "a span", text: "Variación de más de 50%"
    assert_select "a", text: /Variación de más de 50%\s+0/

    get server_price_review_path(token, threshold: 10, group: "large")
    assert_select "a span", text: "Variación de más de 10%"
    assert_select "tbody tr", count: 1, message: "solo el +20%: +10% no pasa de 10"
    assert_select "tbody td", text: "MOTOSIERRA"
    assert_select "a[href*='threshold=10']", minimum: 4, message: "las tarjetas lo conservan"
    assert_select "a[href*='.csv'][href*='threshold=10']"

    get server_price_review_path(token, threshold: "37")
    assert_select "a span", text: "Variación de más de 50%", message: "lo que no está en la lista cae al de omisión"

    get server_price_review_path(token, threshold: [ "10" ])
    assert_response :success

    get server_price_review_path(token, format: :csv, threshold: 10)
    assert_equal "Cambia (variación mayor a 10%)", CSV.parse(response.body.delete_prefix("\uFEFF"))[1].last
    assert_equal "Cambia", CSV.parse(response.body.delete_prefix("\uFEFF"))[2].last
  end

  test "la tabla se pagina y una página que no existe regresa a la primera" do
    rows = (1..30).map { |i| "#{974_200 + i},#{i}" }.join("\n")
    (1..30).each { |i| product(974_200 + i, "PRODUCTO #{i}", 1000) }
    token = review!("CODIGO,PRECIO LISTA S/IVA\n#{rows}\n")

    get server_price_review_path(token)
    assert_select "tbody tr", count: 25
    assert_match(/30 precios\s+· página 1 de 2/, response.body)

    get server_price_review_path(token, page: 2)
    assert_select "tbody tr", count: 5

    get server_price_review_path(token, page: 9, group: "changes", per_page: 50)
    assert_redirected_to server_price_review_path(token, group: "changes", per_page: 50)
  end

  test "aplicar escribe los precios, con el archivo y quién lo cargó, y borra el archivo guardado" do
    token = review!
    post server_price_review_apply_path(token)

    assert_redirected_to server_prices_path
    assert_equal "Se cambió 1 precio. Las partidas nuevas se capturan con el precio nuevo.", flash[:notice]
    override = PriceOverride.sole
    assert_equal [ 974_101, 6900, "stihl.csv", "srv_po" ],
                 [ override.erp_product_id, override.unit_price, override.source_filename, override.loaded_by ]
    assert_nil PriceList::Upload.find(token), "el archivo ya no se necesita"

    follow_redirect!
    assert_match(/stihl\.csv/, response.body)
    assert_match(/Quitar precios cargados/, response.body)
  end

  # Se aplica contra el catálogo de AHORA: si entre revisar y aplicar alguien
  # cargó otro archivo, la cuenta sale de lo que de verdad cambia.
  test "aplicar vuelve a revisar contra el catálogo del momento" do
    token = review!
    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_101, unit_price: 6900)

    post server_price_review_apply_path(token)

    assert_match(/No había precios que cambiar/, flash[:notice])
  end

  test "avisa de los borradores con partidas al precio anterior" do
    capturista = User.create!(erp_person_id: 974_002, username: "cap_po2", password: "x", role: "capturista")
    client = Client.create!(erp_client_key: "PO974", name: "Cliente")
    order = Order.create!(user: capturista, business_round: @round, client: client, kind: "remission")
    order.order_items.create!(@saw.to_order_item_attributes.merge(quantity: 1))

    token = review!
    get server_price_review_path(token)
    assert_match(/Hay 1 pedido en borrador con partidas al precio anterior: cap_po2 \(Cliente\)\./, response.body)
    assert_match(/pide a cada capturista que las quite y las agregue otra vez\./, response.body)

    post server_price_review_apply_path(token)
    assert_match(/Hay 1 pedido en borrador con partidas al precio anterior: cap_po2 \(Cliente\)/, flash[:notice])
    assert_equal 6500, order.order_items.sole.unit_price, "la partida no se toca"
  end

  # Con "atrás" después de aplicar, Turbo restauraba la revisión de su caché
  # y al reenviar "Aplicar" decía "ya no está disponible" (13ª auditoría).
  test "una revisión ya aplicada lo dice al volver a ella, y no se guarda en caché" do
    token = review!
    get server_price_review_path(token)
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"

    post server_price_review_apply_path(token)
    get server_price_review_path(token)
    assert_redirected_to server_prices_path
    assert_equal "Ese archivo ya se aplicó: sus precios están en «Precios cargados».", flash[:notice]

    post server_price_review_apply_path(token)
    assert_equal "Ese archivo ya se aplicó: sus precios están en «Precios cargados».", flash[:notice]
    assert_equal 1, PriceOverride.count, "no aplica dos veces"
  end

  test "un tamaño de página que llega como arreglo no truena" do
    token = review!

    get server_price_review_path(token, per_page: [ "50" ])
    assert_response :success
  end

  test "la revisión se descarga en CSV, renglón por renglón" do
    token = review!
    get server_price_review_path(token, format: :csv)

    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=utf-8"
    assert_match(/revision-stihl\.csv/, response.headers["Content-Disposition"])
    lines = CSV.parse(response.body.delete_prefix("\uFEFF"))
    assert_equal PriceList::ReviewExport::HEADERS, lines.first
    assert_equal [ "2", "974101", "MOTOSIERRA", "6500.0", "6900.0", "+6.2%", "Cambia" ], lines[1]
    assert_equal "Queda igual", lines[2].last
    assert_equal "No se aplica: No está en el catálogo de esta rueda.", lines[3].last
  end

  test "los precios cargados se descargan producto por producto, contra el del ERP" do
    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_101, unit_price: 6900,
                          source_filename: "stihl.xlsx", loaded_by: "srv_po")
    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_999, unit_price: 10)
    PriceOverride.create!(erp_round_id: 1, erp_product_id: 974_102, unit_price: 5)

    get server_prices_path(format: :csv)

    assert_response :success
    assert_match(/precios-cargados-/, response.headers["Content-Disposition"])
    lines = CSV.parse(response.body.delete_prefix("\uFEFF"))
    assert_equal PriceList::LoadedExport::HEADERS, lines.first
    assert_equal [ "974101", "MOTOSIERRA", "6500.0", "6900.0", "+6.2%", "stihl.xlsx", "srv_po" ], lines[1].first(7)
    assert_equal [ "974999", nil, nil, "10.0", nil ], lines[2].first(5), "un código fuera del catálogo sale sin descripción"
    assert_equal 3, lines.size, "solo los de la rueda activa"
  end

  # Sin BOM, Excel en Windows abre el CSV en la codificación local y rompe los
  # acentos (13ª auditoría).
  test "los dos CSV llevan BOM para que Excel respete los acentos" do
    token = review!
    get server_price_review_path(token, format: :csv)
    assert response.body.start_with?("\uFEFFLínea")

    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_101, unit_price: 6900)
    get server_prices_path(format: :csv)
    assert response.body.start_with?("\uFEFFCódigo")
  end

  test "un archivo inservible se rechaza al subirlo, con qué hacer" do
    post server_prices_review_path, params: { file: upload("hola\n", name: "precios.csv") }

    assert_redirected_to server_prices_path
    assert_match(/no tiene el formato del layout/, flash[:alert])
    assert_empty Dir.glob(PriceList::Upload::ROOT.join("*").to_s), "no deja el archivo guardado"
  end

  # Una falla que no es del archivo sube como falla, pero sin dejar el archivo
  # en disco hasta el barrido.
  test "una falla inesperada al leer no deja el archivo guardado" do
    original = PriceList::Upload.instance_method(:read)
    PriceList::Upload.define_method(:read) { raise "falla inesperada" }

    assert_raises(RuntimeError) { post server_prices_review_path, params: { file: upload("CODIGO,PRECIO LISTA S/IVA\n974101,1\n") } }
    assert_empty Dir.glob(PriceList::Upload::ROOT.join("*").to_s)
  ensure
    PriceList::Upload.define_method(:read, original)
  end

  test "sin archivo lo pide" do
    post server_prices_review_path

    assert_redirected_to server_prices_path
    assert_equal "Elige el archivo de precios que quieres revisar.", flash[:alert]
  end

  test "una ficha que no existe o que no tiene forma de ficha no rompe nada" do
    [ "0" * 32, "no-es-ficha" ].each do |token|
      get server_price_review_path(token)
      assert_redirected_to server_prices_path
      assert_match(/ya no está disponible/, flash[:alert])

      post server_price_review_apply_path(token)
      assert_redirected_to server_prices_path
    end
    assert_equal 0, PriceOverride.count
  end

  test "quitar los precios cargados vuelve a los del ERP" do
    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_101, unit_price: 6900)
    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_102, unit_price: 1100)

    delete server_prices_destroy_path

    assert_equal "Se quitaron 2 precios cargados. Desde ahora se captura con los precios del ERP.", flash[:notice]
    assert_equal 0, PriceOverride.count
    assert_equal 6500, @saw.reload.capture_price
  end

  test "con un sync corriendo no se revisa, ni se aplica, ni se quita" do
    token = review!
    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_102, unit_price: 1100)
    SyncRun.create!(kind: "down", started_at: Time.current, pid: Process.pid)

    post server_prices_review_path, params: { file: upload("CODIGO,PRECIO LISTA S/IVA\n974101,1\n") }
    assert_equal ApplicationController::SYNC_PAUSE_MESSAGE, flash[:alert]
    post server_price_review_apply_path(token)
    assert_equal ApplicationController::SYNC_PAUSE_MESSAGE, flash[:alert]
    delete server_prices_destroy_path
    assert_equal ApplicationController::SYNC_PAUSE_MESSAGE, flash[:alert]

    assert_equal [ [ 974_102, 1100 ] ], PriceOverride.pluck(:erp_product_id, :unit_price)
  end

  test "sin rueda activa manda primero a obtener la información" do
    @round.update!(active: false)

    get server_prices_path

    assert_redirected_to root_path
    assert_match(/Primero obtén la información de la rueda/, flash[:alert])
  end

  test "es solo para el equipo servidor" do
    User.create!(erp_person_id: 974_003, username: "cap_po3", password: "secret123", role: "capturista", active: true)
    login_as "cap_po3"

    get server_prices_path
    assert_redirected_to root_path

    post server_prices_review_path, params: { file: upload("CODIGO,PRECIO LISTA S/IVA\n974101,1\n") }
    delete server_prices_destroy_path
    assert_equal 0, PriceOverride.count
  end

  test "la tarjeta del panel lleva a la pantalla y dice cuántos hay cargados" do
    PriceOverride.create!(erp_round_id: 974_001, erp_product_id: 974_101, unit_price: 6900)

    get root_path

    assert_select "a[href=?]", server_prices_path, text: /Cambiar\s*precios/
    assert_match(/1 precio cargado desde archivo/, response.body)
  end

  test "con un sync corriendo la tarjeta del panel queda bloqueada" do
    SyncRun.create!(kind: "down", started_at: Time.current, pid: Process.pid)

    get root_path

    assert_select "a[href=?]", server_prices_path, count: 0
    assert_select "[aria-disabled=true]", text: /Cambiar\s*precios/
  end
end
