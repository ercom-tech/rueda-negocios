# Filtros del reporte de pedidos capturados.
#
# Un solo objeto arma el alcance para el listado, el resumen por estatus y el
# conteo del paginador, de modo que no puedan divergir (que el resumen diga 68
# y el paginador 71). Se aplica SOBRE el scope ya acotado por rol, así que un
# capturista nunca puede filtrar hacia pedidos ajenos.
#
# El estatus se aplica aparte (`apply_status`): las tarjetas del resumen SON el
# filtro de estatus y tienen que seguir mostrando el panorama completo para
# poder saltar entre ellas, así que el resumen se calcula con todo lo demás
# aplicado pero sin el estatus.
#
# Pendiente (backlog): proveedor, marca y producto. Esos son de las PARTIDAS y
# van con `EXISTS`, no con `JOIN` — unir `order_items` repetiría el pedido por
# cada partida que coincida e inflaría el importe del resumen, que ya hace su
# propio join para sumar.
class OrdersFilter
  attr_reader :user_id, :client_id, :salesperson_id, :from, :to, :status

  def initialize(params)
    @user_id        = id_param(params[:user_id])
    @client_id      = id_param(params[:client_id])
    @salesperson_id = id_param(params[:salesperson_id])
    @from           = date_param(params[:from])
    @to             = date_param(params[:to])
    @status         = params[:status].presence_in(Order.statuses.keys)
  end

  def apply_without_status(scope)
    scope = scope.where(user_id: user_id)     if user_id
    scope = scope.where(client_id: client_id) if client_id
    scope = scope.joins(:client).where(clients: { salesperson_id: salesperson_id }) if salesperson_id
    scope = scope.where(created_at: day_start(from)..) if from
    scope = scope.where(created_at: ..day_end(to))     if to
    scope
  end

  def apply_status(scope)
    status ? scope.where(status: status) : scope
  end

  # Parámetros vigentes, para que los enlaces (paginador, tarjetas de estatus)
  # conserven el filtro. `page` nunca viaja: cambiar un filtro debe regresar a
  # la primera página o se cae en uma página que ya no existe.
  def to_params
    { user_id: user_id, client_id: client_id, salesperson_id: salesperson_id,
      from: from&.to_s, to: to&.to_s, status: status }.compact
  end

  def any?
    to_params.any?
  end

  private

  def id_param(value)
    value.presence&.to_i
  end

  def date_param(value)
    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end

  # Las fechas se interpretan en la hora LOCAL del equipo, igual que la columna
  # Fecha del reporte (`created_at.localtime`). Con `Time.zone` en UTC, un
  # pedido capturado a las 19:00 del día 10 se guarda como 01:00 del 11: filtrar
  # en UTC lo dejaría fuera del mismo día que la pantalla le muestra al usuario.
  def day_start(date)
    ::Time.new(date.year, date.month, date.day, 0, 0, 0)
  end

  def day_end(date)
    ::Time.new(date.year, date.month, date.day, 23, 59, 59)
  end
end
