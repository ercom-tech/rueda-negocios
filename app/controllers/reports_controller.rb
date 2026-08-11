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
    scope      = orders_scope
    @summary   = scope.totals_by_status
    @all_scope = current_user.can_see_all_orders?
    @pagy, @orders = pagy(scope.includes(:user, :order_items, client: :salesperson).order(created_at: :desc),
                          limit: page_size)
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

  def require_round
    return if Setting.instance.selected_round_erp_id.present? || active_round.present?

    redirect_to root_path, alert: "No hay rueda en curso."
  end
end
