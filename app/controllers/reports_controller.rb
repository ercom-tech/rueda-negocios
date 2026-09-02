require "csv"

class ReportsController < ApplicationController
  include Pagy::Backend

  # Hub de "Reportes de venta": muestra las opciones de reporte.
  layout "auth"

  # Sin rueda en curso no hay nada que reportar. Para el server el criterio es
  # la selección (puede ver reportes desde que elige rueda, aunque estén
  # vacíos); a un capturista sin rueda activa ya lo expulsó el guard de sesión.
  before_action :require_round

  # Una página que ya no existe (marcador viejo, o la lista encogió tras cerrar
  # la rueda) daba la pantalla de error de Rails en plena laptop del evento.
  rescue_from Pagy::OverflowError do
    # Se rearma con los filtros ya saneados, no con los parámetros crudos de la
    # petición: un `?host=` en la URL se colaría al enlace de regreso. Y vuelve
    # al reporte en el que se estaba: mandar al de pedidos desde el de
    # productos sería perder los filtros sin explicación.
    if action_name == "products"
      redirect_to products_report_path(supplier_id: @supplier_id, brand_id: @brand_id,
                                       per_page: page_size)
    else
      redirect_to captured_orders_report_path((@filter&.to_params || {}).merge(per_page: page_size))
    end
  end

  def index; end

  # Reporte de pedidos capturados. Un capturista ve solo los suyos; el
  # equipo-servidor ve todos (para transmitirlos al ERP). Paginado: en un
  # evento grande la lista completa se vuelve pesada para la tablet.
  def captured_orders
    @all_scope = current_user.can_see_all_orders?
    @filter    = OrdersFilter.new(params)
    @sort      = OrdersSort.new(params)

    # El resumen se calcula con TODOS los filtros menos el de estatus: sus
    # tarjetas son el filtro de estatus y deben seguir mostrando el panorama
    # completo para poder saltar entre ellas.
    filtered    = @filter.apply_without_status(orders_scope)
    @products   = @filter.matching_products
    @summary    = filtered.totals_by_status(@products)
    @options    = filter_options
    @page_sizes = PAGE_SIZES

    # El orden se aplica ANTES de paginar (dentro de `OrdersSort#apply`), o la
    # tabla se vería ordenada dentro de una página que siempre trae los mismos
    # pedidos. `@products` va porque con filtro de partida las columnas
    # Renglones y Total muestran —y por tanto ordenan por— lo que coincide.
    listado = @sort.apply(@filter.apply_status(filtered), @products)
                   .includes(:user, :order_items, client: :salesperson)
    @pagy, @orders = pagy(listado, limit: page_size)
    @matching = matching_totals(@orders, @products)
  end

  # Reporte de productos: piezas vendidas por producto en la rueda. Mismo
  # alcance por rol que el de pedidos (`accessible_orders`), así que un
  # capturista ve lo que él capturó y el equipo-servidor ve todo.
  #
  # HTML y CSV comparten TODO menos la presentación: el archivo sale con los
  # mismos filtros que se están viendo, porque es la misma acción.
  def products
    @all_scope   = current_user.can_see_all_orders?
    # Por `ParamSanitizing` y no `to_i`: un `?supplier_id[]=1` llega como
    # arreglo y `to_i` levanta NoMethodError — la pantalla de error de Rails.
    @supplier_id = ParamSanitizing.id(params[:supplier_id])
    @brand_id    = ParamSanitizing.id(params[:brand_id])
    @options     = product_report_options
    # Un id que no está en las opciones se ignora: los combos acotan al
    # universo del capturista, y sin esto un `?supplier_id=` a mano lo saltaría.
    @supplier_id = nil unless @options[:suppliers].any? { |(_, id)| id == @supplier_id }
    @brand_id    = nil unless @options[:brands].any? { |(_, id)| id == @brand_id }

    @sales = ProductSales.new(accessible_orders, supplier_id: @supplier_id, brand_id: @brand_id)

    respond_to do |format|
      format.html do
        @page_sizes = PAGE_SIZES
        # `Pagy.new` a mano y no `pagy_array`: esa extra no está cargada y
        # activarla globalmente para una pantalla no se paga.
        rows  = @sales.catalog_rows
        # `page` saneado: un `?page[]=2` hace que Pagy levante
        # `Pagy::VariableError`, que no es `OverflowError` y el `rescue_from`
        # de arriba no atrapa.
        @pagy = Pagy.new(count: rows.size, page: ParamSanitizing.page(params[:page]), limit: page_size)
        @rows = rows[@pagy.offset, @pagy.limit] || []
      end
      # Las descargas van COMPLETAS, sin paginar: el archivo se abre para
      # trabajarlo, y uno con 25 de 300 renglones sería una trampa silenciosa.
      format.csv do
        send_data products_csv, filename: products_filename("csv"), type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data products_xlsx, filename: products_filename("xlsx"),
                  type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      end
    end
  end

  # Sugerencias del filtro de producto. Acotadas al universo de quien mira: al
  # capturista no se le ofrecen productos que jamás podrían aparecer en sus
  # pedidos.
  def product_options
    universe = current_user.can_see_all_orders? ? Product.all : current_user.product_universe(active_round)
    found = params[:q].present? ?
      universe.search(params[:q]).includes(:price).limit(Product::SEARCH_LIMIT + 1).to_a : []
    truncated = found.size > Product::SEARCH_LIMIT
    @products = found.first(Product::SEARCH_LIMIT)
    render partial: "product_options",
           locals: { products: @products, truncated: truncated }, layout: false
  end

  private

  # Renglones por página que se ofrecen. En tablet 25 es cómodo; el servidor,
  # revisando todo antes de transmitir, agradece 100. Lista cerrada para que
  # nadie pida 5,000 renglones por URL y tumbe la pantalla.
  PAGE_SIZES = [ 25, 50, 100 ].freeze

  # UN solo lugar arma el alcance: de aquí salen el listado, el resumen por
  # estatus y el conteo del paginador, para que no puedan divergir. El alcance
  # por rol es `accessible_orders` (ApplicationController), compartido con
  # OrdersController; los filtros se aplican SOBRE él en `OrdersFilter`.
  def orders_scope
    accessible_orders
  end

  def page_size
    size = params[:per_page].to_i
    PAGE_SIZES.include?(size) ? size : PAGE_SIZES.first
  end

  # Opciones de los combos. Los catálogos de una rueda son chicos (decenas de
  # clientes y vendedores, un puñado de capturistas), así que caben en combos
  # con filtro de texto — no hacen falta buscadores. "Usuario crea" solo para
  # el equipo-servidor: un capturista ya está acotado a lo suyo y el combo le
  # ofrecería nombres que no puede consultar.
  def filter_options
    {
      users: (User.capturista.order(:name, :username).map { |u| [ u.full_name.presence || u.username, u.id ] } if @all_scope),
      clients: Client.order(:name).map { |c| [ "#{c.erp_client_key} — #{c.name}", c.id ] },
      salespeople: Salesperson.order(:name).map { |s| [ "#{s.erp_salesperson_id} — #{s.name}", s.id ] },
      # Proveedores y marcas del universo de quien mira: al capturista no se le
      # ofrecen opciones que jamás podrían aparecer en sus pedidos.
      suppliers: (@all_scope ? Supplier.order(:name) : available_suppliers).map { |s| [ s.name, s.id ] },
      brands: (@all_scope ? Brand.order(:name) : available_brands).map { |b| [ b.name, b.id ] }
    }.compact
  end

  # Importe y renglones POR PEDIDO de la página, contando solo las partidas que
  # coinciden con el filtro de proveedor/marca/producto. Una sola consulta para
  # los 25 pedidos visibles, en vez de recalcular en Ruby pedido por pedido.
  def matching_totals(orders, products)
    return nil if products.nil? || orders.empty?

    OrderItem.where(order_id: orders.map(&:id), product_id: products)
             .group(:order_id)
             .pluck(:order_id, Arel.sql("COUNT(*)"),
                    Arel.sql("COALESCE(SUM(#{Order::ITEM_TOTAL_SQL}), 0)"))
             .to_h { |id, count, total| [ id, { count: count, total: total } ] }
  end

  # Combos del reporte de productos: SOLO proveedor y marca, y acotados al
  # universo de quien mira — mismo criterio que los del reporte de pedidos.
  def product_report_options
    {
      suppliers: (@all_scope ? Supplier.order(:name) : available_suppliers).map { |s| [ s.name, s.id ] },
      brands: (@all_scope ? Brand.order(:name) : available_brands).map { |b| [ b.name, b.id ] }
    }
  end

  # "Origen" al final: en pantalla el fuera de catálogo va en un bloque APARTE
  # —mezclarlo con el catálogo sería engañoso, dice la propia vista— pero un
  # archivo es una sola lista. Sin esta columna, ordenar por Cantidad en Excel
  # juntaba los dos universos sin ninguna marca (9ª auditoría).
  PRODUCTS_CSV_HEADERS = [ "Código FECEGO", "Descripción", "Modelo", "No. de parte",
                          "Cantidad", "Regalos", "SKU proveedor", "Origen" ].freeze

  CATALOG_ORIGIN = "Catálogo".freeze
  GENERIC_ORIGIN = "Fuera de catálogo".freeze

  # Las filas del archivo, cada una con su origen. Las dos exportaciones salen
  # de aquí para que no puedan divergir entre sí ni de la pantalla.
  def products_file_rows
    (@sales.catalog_rows.map { |row| [ row, CATALOG_ORIGIN ] } +
     @sales.generic_rows.map { |row| [ row, GENERIC_ORIGIN ] }).map do |row, origin|
      [ row.code, row.description, row.model, row.part_number,
       row.sold, row.gifted, row.sku, origin ]
    end
  end

  # Nota al pie del archivo cuando el filtro deja fuera piezas del genérico. La
  # pantalla lo avisa con un párrafo y el archivo lo omitía en silencio: quien
  # abre el .xlsx no tenía forma de saber que faltaba algo.
  def products_excluded_note
    n = @sales.hidden_generic_quantity
    return nil unless n.positive?

    [ n == 1 ? "No incluye 1 pieza fuera de catálogo, excluida por el filtro." :
               "No incluye #{number_or_blank(n)} piezas fuera de catálogo, excluidas por el filtro." ]
  end

  # El BOM (`﻿`) NO es adorno: sin él, Excel en Windows abre el archivo en
  # la codificación local y "MARTILLO DEMOLEDOR 3/4" sale con los acentos rotos.
  # Es la trampa clásica de exportar CSV en español, y no se ve al probarlo en
  # una Mac.
  def products_csv
    CSV.generate(String.new("﻿")) do |csv|
      csv << PRODUCTS_CSV_HEADERS
      products_file_rows.each do |code, description, model, part_number, sold, gifted, sku, origin|
        csv << [ code, description, model, part_number,
                number_or_blank(sold), number_or_blank(gifted), sku, origin ]
      end
      if (note = products_excluded_note)
        csv << []
        csv << note
      end
    end
  end

  # Las cantidades salen sin ceros insignificantes (2 y no 2.000): la columna
  # es `decimal(14,3)` porque hay productos a granel, pero el 99% son piezas
  # enteras y "2.000" en una celda de Excel se lee como error de captura.
  def number_or_blank(value)
    return nil if value.nil? || value.zero?

    value.to_d.to_s("F").sub(/\.?0+\z/, "")
  end

  # En el .xlsx las cantidades van como NÚMERO, no como texto: es la ventaja
  # real del formato sobre el CSV — se pueden sumar y ordenar en Excel sin
  # convertir nada. Una celda vacía en vez de 0 para que el promedio de la
  # columna de regalos no cuente los renglones sin regalo.
  def number_or_nil(value)
    return nil if value.nil? || value.zero?

    value.to_f
  end

  def products_xlsx
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Productos") do |sheet|
      header = sheet.styles.add_style(b: true, bg_color: "111111", fg_color: "FFFFFF")
      sheet.add_row PRODUCTS_CSV_HEADERS, style: header
      # Los tipos se declaran, no se adivinan: caxlsx ve "009711" y lo guarda
      # como número 9711, perdiendo los ceros a la izquierda — y el código
      # FECEGO va SIEMPRE a 6 dígitos (es como lo muestra el ERP y como lo
      # teclea la gente). El No. de parte tiene el mismo riesgo. Las cantidades
      # sí van numéricas a propósito: es la ventaja del xlsx sobre el CSV.
      types = [ :string, :string, :string, :string, :float, :float, :string, :string ]
      products_file_rows.each do |code, description, model, part_number, sold, gifted, sku, origin|
        sheet.add_row [ code, description, model, part_number,
                       number_or_nil(sold), number_or_nil(gifted), sku, origin ],
                      types: types
      end
      if (note = products_excluded_note)
        sheet.add_row []
        sheet.add_row note, types: [ :string ]
      end
      # Anchos a ojo del contenido real: la descripción del ERP es larga y sin
      # esto sale la columna estándar, que la corta en todas las filas.
      sheet.column_widths 12, 55, 14, 14, 10, 10, 16, 18
      # Congelar el encabezado: son cientos de renglones y sin esto se pierde
      # de vista qué columna es cuál al bajar.
      sheet.sheet_view.pane { |pane| pane.top_left_cell = "A2"; pane.state = :frozen; pane.y_split = 1 }
    end
    package.to_stream.read
  end

  # Nombre con la fecha y el filtro, para que dos descargas del mismo día no se
  # pisen en la carpeta de Descargas.
  def products_filename(extension)
    parts = [ "productos" ]
    parts << Supplier.find_by(id: @supplier_id)&.name if @supplier_id
    parts << Brand.find_by(id: @brand_id)&.name if @brand_id
    parts << Time.current.strftime("%Y-%m-%d")
    "#{parts.compact.join('-').parameterize}.#{extension}"
  end

  def require_round
    return if Setting.instance.selected_round_erp_id.present? || active_round.present?

    redirect_to root_path, alert: "No hay rueda en curso."
  end
end
