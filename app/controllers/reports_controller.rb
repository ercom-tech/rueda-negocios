class ReportsController < ApplicationController
  include Pagy::Backend

  # Hub de "Reportes de venta": muestra las opciones de reporte.
  layout "auth"

  # Sin rueda en curso no hay nada que reportar. Para el server el criterio es
  # la selección (puede ver reportes desde que elige rueda, aunque estén
  # vacíos); a un capturista sin rueda activa ya lo expulsó el guard de sesión.
  before_action :require_round

  def index; end

  # Reporte de pedidos capturados. Un capturista ve solo los suyos; el
  # equipo-servidor ve todos (para transmitirlos al ERP). Paginado: en un
  # evento grande la lista completa se vuelve pesada para la tablet.
  def captured_orders
    @all_scope = current_user.can_see_all_orders?
    @filter    = OrdersFilter.new(params)

    # El resumen se calcula con TODOS los filtros menos el de estatus: sus
    # tarjetas son el filtro de estatus y deben seguir mostrando el panorama
    # completo para poder saltar entre ellas.
    filtrado   = @filter.apply_without_status(orders_scope)
    @productos = @filter.matching_products
    @summary   = filtrado.totals_by_status(@productos)
    @options   = filter_options

    @pagy, @orders = pagy(@filter.apply_status(filtrado)
                                 .includes(:user, :order_items, client: :salesperson)
                                 .order(created_at: :desc),
                          limit: page_size)
    @matching = matching_totals(@orders, @productos)
  end

  # Sugerencias del filtro de producto. Acotadas al universo de quien mira: al
  # capturista no se le ofrecen productos que jamás podrían aparecer en sus
  # pedidos.
  def product_options
    universo = current_user.can_see_all_orders? ? Product.all : current_user.product_universe(active_round)
    @products = params[:q].present? ? universo.search(params[:q]).includes(:price).limit(10) : Product.none
    render partial: "product_options", locals: { products: @products }, layout: false
  end

  private

  # Renglones por página que se ofrecen. En tablet 25 es cómodo; el servidor,
  # revisando todo antes de transmitir, agradece 100. Lista cerrada para que
  # nadie pida 5,000 renglones por URL y tumbe la pantalla.
  PAGE_SIZES = [ 25, 50, 100 ].freeze

  # UN solo lugar arma el alcance: de aquí salen el listado, el resumen por
  # estatus y el conteo del paginador, para que no puedan divergir. Cuando
  # entren los filtros del reporte, se aplican aquí y los tres los heredan.
  def orders_scope
    current_user.can_see_all_orders? ? Order.all : current_user.orders
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

  def require_round
    return if Setting.instance.selected_round_erp_id.present? || active_round.present?

    redirect_to root_path, alert: "No hay rueda en curso."
  end
end
