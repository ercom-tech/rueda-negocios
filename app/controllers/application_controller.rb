class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login
  before_action :require_current_session
  before_action :require_round_for_capturista

  helper_method :current_user, :logged_in?, :active_round, :available_suppliers,
                :current_supplier, :available_brands, :current_brand, :can_edit_order?,
                :can_resolve_draft?, :report_back_path

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # Un pedido lo edita solo su capturista (y mientras no esté transmitido).
  # El rol server puede VER cualquier pedido, pero no editarlo.
  def can_edit_order?(order)
    order.editable? && order.user_id == current_user&.id
  end

  # El equipo-servidor puede RESOLVER un borrador ajeno: guardarlo o
  # descartarlo, tal como está. No editarlo — ni sus partidas ni su encabezado.
  #
  # Existe porque un borrador abandonado —el capturista se fue, la tablet
  # murió— bloquea las TRES operaciones del panel (obtener información,
  # transmitir y cerrar rueda) y dejaba a la laptop sin salida en pleno evento.
  # Acotado a borradores a propósito: un pedido capturado ya tiene folio y es
  # transmisible, y borrarlo es una decisión distinta.
  # Solo PEDIDOS: el permiso existe porque un borrador bloquea las operaciones
  # del panel, y una cotización no bloquea ninguna — el servidor la consulta.
  def can_resolve_draft?(order)
    current_user&.server? && order.sale? && order.draft?
  end

  # Un pedido o cotización que YA NO EXISTE, con la pantalla todavía abierta en
  # otro equipo. Es nuevo con las cotizaciones: obtener información y cerrar la
  # rueda las borran sin que nada lo impida (un borrador de pedido, en cambio,
  # bloquea las dos). El siguiente toque sobre esa pantalla caía en "No
  # encontramos esa pantalla", sin explicación; ahora regresa al menú y dice
  # qué pasó. Solo cuando el registro no existe: uno que existe y no es del
  # usuario sigue siendo 404, que es la respuesta correcta a un id ajeno.
  ORDER_GONE_MESSAGE = "Ese pedido o cotización ya no está en esta laptop: se descartó, " \
                       "o se borró al obtener la información o al cerrar la rueda.".freeze

  #
  # El id pasa por `ParamSanitizing` y la consulta va en forma de hash: con
  # `Order.exists?(params[:order_id])` un `?order_id[]=<condición>` llegaba
  # como arreglo, y un arreglo en `exists?` es un FRAGMENTO SQL. Con la
  # respuesta distinta para verdadero (404) y falso (302), cualquier
  # capturista tenía un oráculo para leer cualquier tabla (16ª auditoría,
  # ALTA). Lo que no es un id válido no puede ser un registro que desapareció:
  # sigue el error original.
  def order_gone(error)
    id = ParamSanitizing.id(params[:order_id] || params[:id])
    raise error if id.nil? || Order.exists?(id: id)

    # El buscador de producto trae sus sugerencias con un fetch plano que
    # SIGUE la redirección: sin esta rama, el menú entero se inyectaba dentro
    # del panel de sugerencias. El aviso va dentro del panel, con su salida.
    if action_name == "product_options"
      render partial: "orders/order_gone", layout: false
    else
      redirect_to root_path, alert: ORDER_GONE_MESSAGE
    end
  end

  # Un pedido transmitido al ERP ya no se edita. Respondía `head :forbidden`
  # y, con la pantalla abierta mientras el servidor transmitía, la cantidad
  # regresaba sola y el modal de promoción se cerraba sin decir nada (16ª
  # auditoría). Se vuelve a la captura COMPLETA, no solo a la tabla: el badge
  # tiene que decir "Transmitido" y los botones de editar desaparecer.
  # `see_other`: es la respuesta a un PATCH/POST/DELETE, y Turbo la sigue.
  ORDER_TRANSMITTED_MESSAGE = "Este pedido ya se transmitió al ERP: ya no se puede cambiar. Así quedó.".freeze

  def ensure_editable
    return if @order.editable?

    redirect_to order_path(@order), alert: ORDER_TRANSMITTED_MESSAGE, status: :see_other
  end

  # Pedidos que el usuario puede LEER: el capturista los suyos, el
  # equipo-servidor todos (los transmite y los revisa). La escritura va por
  # `current_user.orders`, o por `with_locked_writable_order` (OrdersController)
  # donde el servidor puede resolver un borrador ajeno. Vive aquí, y no repetido en cada controller, para
  # que la regla de visibilidad se cambie en un solo lugar.
  def accessible_orders
    current_user.can_see_all_orders? ? Order.all : current_user.orders
  end

  # Regreso al reporte CON sus filtros, cuando se llegó al pedido desde ahí.
  # Se toma del referer porque así vuelven también el estatus y la página; sin
  # esto, el equipo-servidor que revisa pedidos antes de transmitir tenía que
  # rearmar los siete filtros a mano en cada regreso. nil si no se vino de ahí.
  #
  # Se valida el host: un referer externo no debe convertirse en un enlace de
  # regreso hacia afuera.
  def report_back_path
    return @report_back_path if defined?(@report_back_path)

    @report_back_path = begin
      uri = URI.parse(request.referer.to_s)
      same_site = uri.host.blank? || (uri.host == request.host && uri.port == request.port)
      report = uri.path.in?([ captured_orders_report_path, estimates_report_path ])
      [ uri.path, uri.query ].compact_blank.join("?") if same_site && report
    rescue URI::InvalidURIError
      nil
    end
  end

  def logged_in?
    current_user.present?
  end

  # Rueda activa cargada en esta laptop.
  def active_round
    return @active_round if defined?(@active_round)

    @active_round = BusinessRound.active.first
  end

  # Proveedores que el capturista representa en la rueda activa (0, 1 o varios).
  def available_suppliers
    return @available_suppliers if defined?(@available_suppliers)

    @available_suppliers = logged_in? ? current_user.suppliers_in(active_round) : []
  end

  # Proveedor "activo" en la sesión. Si hay uno solo, se autoselecciona; si hay
  # varios, respeta la elección guardada (o cae al primero). Hoy es solo
  # contexto/etiqueta: NO restringe la captura (un pedido puede mezclar
  # proveedores). Esa regla se definirá más adelante si cambia.
  def current_supplier
    return @current_supplier if defined?(@current_supplier)

    @current_supplier = available_suppliers.find { |s| s.id == session[:supplier_id] } ||
                        available_suppliers.first
  end

  # Marcas del capturista en la rueda activa — espejo de proveedores.
  def available_brands
    return @available_brands if defined?(@available_brands)

    @available_brands = logged_in? ? current_user.brands_in(active_round) : []
  end

  # Marca "activa" de la sesión (mismo carácter que current_supplier: solo
  # contexto/etiqueta, no restringe la captura).
  def current_brand
    return @current_brand if defined?(@current_brand)

    @current_brand = available_brands.find { |b| b.id == session[:brand_id] } ||
                     available_brands.first
  end

  def require_login
    return if logged_in?

    redirect_to login_path, alert: "Inicia sesión para continuar."
  end

  # Sesión única por usuario: si el token de la cookie ya no coincide con el
  # del usuario (alguien inició sesión con ese login en otro equipo), esta
  # sesión quedó desplazada y se cierra. "El último login gana" — no hay
  # candados fantasma: cerrar el navegador sin logout no bloquea a nadie.
  def require_current_session
    return unless logged_in?
    return if session[:session_token] == current_user.session_token

    reset_session
    redirect_to login_path, alert: "Tu usuario inició sesión en otro equipo. " \
                                   "Vuelve a entrar si quieres usar este."
  end

  # Sin rueda cargada un capturista no tiene nada que operar. El login ya lo
  # bloquea en la puerta; este guard expulsa además a los que tenían sesión
  # viva cuando el server cerró la rueda (o el sync-down reemplazó usuarios).
  def require_round_for_capturista
    return unless logged_in?
    return if current_user.can_see_all_orders? || active_round.present?

    reset_session
    redirect_to login_path, alert: SessionsController.no_round_message
  end

  # Mientras corre un sync, la captura se pausa. Cubre dos fallas distintas con
  # el mismo mecanismo:
  #
  # - **Obtener información** vacía el catálogo dentro de su transacción. Un
  #   INSERT concurrente con FK a un cliente o un producto se queda esperando
  #   el lock y luego revienta con violación de llave foránea: el capturista
  #   veía la pantalla de error del sistema y no sabía si su pedido existía.
  # - **Transmitir pedidos** arma el payload, hace el POST y hasta después
  #   marca `transmitted`. Un pedido `captured` sigue siendo editable por su
  #   dueño, así que un cambio en esa ventana dejaba al ERP con la versión
  #   vieja y a la pantalla con la nueva, sin aviso en ningún lado.
  #
  # Solo bloquea ESCRITURAS: leer un pedido, el reporte y el PDF siguen
  # disponibles. Los syncs duran segundos y se operan desde la oficina, así que
  # el costo para el capturista es un aviso, no una pausa que se note.
  SYNC_PAUSE_MESSAGE = "Se está actualizando la información. " \
                       "Espera un momento y vuelve a intentar.".freeze

  def pause_writes_during_sync
    return unless SyncRun.running.exists?

    if request.format.turbo_stream?
      # 422 y no 200: Turbo pinta el flash igual, pero `turbo:submit-end`
      # llega con `success: false`. Con 200, la palomita "Guardado ✓"
      # aparecía JUNTO al aviso de "vuelve a intentar" y el capturista le
      # creía a la palomita (5ª auditoría, confirmado en navegador).
      render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash",
                                                         locals: { alert: SYNC_PAUSE_MESSAGE }),
             status: :unprocessable_entity
    else
      redirect_back fallback_location: root_path, alert: SYNC_PAUSE_MESSAGE
    end
  end

  # Restringe una acción al rol server (operador del sync).
  def require_server
    return if current_user&.can_see_all_orders?

    redirect_to root_path, alert: "Esta sección es solo para el equipo servidor."
  end
end
