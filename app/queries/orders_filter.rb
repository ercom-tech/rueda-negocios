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
# Proveedor, marca y producto NO son del pedido sino de sus partidas
# ("pedidos que traen al menos una partida de MAKITA"). Los tres se reducen a
# un conjunto de productos (`matching_products`) y se aplican con un `IN` sobre
# `order_items.product_id`, nunca con un `JOIN` a `order_items`: unir
# duplicaría el pedido por cada partida que coincida e inflaría el importe del
# resumen, que ya hace su propio join para sumar.
#
# Con uno de esos filtros activo, los importes que se muestran son los de las
# PARTIDAS QUE COINCIDEN, no los del pedido completo (decisión del usuario,
# 2026-08-10): quien pregunta "¿cuánto vendió MAKITA?" quiere la venta de
# MAKITA, no el tamaño de los pedidos donde aparece — y con dos proveedores los
# totales se traslaparían. La pantalla lo dice explícitamente (`items_label`).
class OrdersFilter
  attr_reader :user_id, :client_id, :salesperson_id, :from, :to, :status,
              :supplier_id, :brand_id, :product_q

  def initialize(params)
    @user_id        = id_param(params[:user_id])
    @client_id      = id_param(params[:client_id])
    @salesperson_id = id_param(params[:salesperson_id])
    @from           = date_param(params[:from])
    @to             = date_param(params[:to])
    @status         = params[:status].presence_in(Order.statuses.keys)
    @supplier_id    = id_param(params[:supplier_id])
    @brand_id       = id_param(params[:brand_id])
    @product_q      = params[:product_q].presence&.strip
  end

  # ¿Hay algún filtro de partida? Es lo que cambia el significado de los
  # importes de la pantalla.
  def items?
    supplier_id.present? || brand_id.present? || product_q.present?
  end

  # Productos que satisfacen los filtros de partida (intersección de los tres),
  # o nil si no hay ninguno. Se devuelve como subconsulta de ids: no se
  # materializa en Ruby porque un proveedor puede tener miles de productos.
  def matching_products
    return nil unless items?

    scope = Product.all
    scope = scope.where(brand_id: brand_id) if brand_id
    scope = scope.joins(:product_suppliers).where(product_suppliers: { supplier_id: supplier_id }) if supplier_id
    scope = scope.search(product_q) if product_q
    scope.select(:id)
  end

  def apply_without_status(scope)
    scope = scope.where(user_id: user_id)     if user_id
    scope = scope.where(client_id: client_id) if client_id
    scope = scope.joins(:client).where(clients: { salesperson_id: salesperson_id }) if salesperson_id
    scope = scope.where(created_at: day_start(from)..) if from
    scope = scope.where(created_at: ..day_end(to))     if to
    if (productos = matching_products)
      scope = scope.where(id: OrderItem.where(product_id: productos).select(:order_id))
    end
    scope
  end

  # Aviso para la pantalla cuando los importes dejan de ser los del pedido
  # completo. nil si no hay filtro de partida.
  def items_label(supplier_name: nil, brand_name: nil)
    return nil unless items?

    quienes = [ supplier_name, brand_name ].compact
    texto   = "Importes de las partidas"
    texto  += " de #{quienes.to_sentence(two_words_connector: ' y ', last_word_connector: ' y ')}" if quienes.any?
    # El producto se busca por texto, así que no se enuncia igual: un código
    # suelto ("de \"037857\"") se lee como si fuera un proveedor.
    texto  += " que coinciden con \"#{product_q}\"" if product_q
    texto
  end

  def apply_status(scope)
    status ? scope.where(status: status) : scope
  end

  # Parámetros vigentes, para que los enlaces (paginador, tarjetas de estatus)
  # conserven el filtro. `page` nunca viaja: cambiar un filtro debe regresar a
  # la primera página o se cae en uma página que ya no existe.
  def to_params
    { user_id: user_id, client_id: client_id, salesperson_id: salesperson_id,
      from: from&.to_s, to: to&.to_s, status: status,
      supplier_id: supplier_id, brand_id: brand_id, product_q: product_q }.compact
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
