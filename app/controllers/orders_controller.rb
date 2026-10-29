class OrdersController < ApplicationController
  layout "auth"

  rescue_from ActiveRecord::RecordNotFound, with: :order_gone

  # Crear es del capturista. El equipo-servidor consulta (y resuelve borradores
  # ajenos de pedido): su menú no tiene las tarjetas, pero tecleando la URL
  # levantaba cotizaciones y pedidos a su nombre — y un pedido así se
  # transmitiría con el operador como capturista (15ª auditoría).
  before_action :require_capturista, only: %i[new create]
  # Solo las acciones que ESCRIBEN: abrir un pedido, el resumen y el PDF siguen
  # disponibles mientras corre un sync.
  before_action :pause_writes_during_sync, only: %i[create update destroy capture observations]

  # Paso 1 — encabezado. `client_key` carga al cliente (clave exacta o, si no,
  # el primer match por nombre).
  def new
    if params[:client_key].present?
      # El buscador puede traer "CLAVE - Nombre"; toma la clave (primer token).
      @client = client_from_key(params[:client_key])
    end
    @cfdi_uses = CfdiUse.order(:code)
    @order = Order.new(client: @client, document: document_param)
    apply_header_defaults if @client
  end

  # Sugerencias del autocompletado (clave o nombre).
  def client_options
    # Uno de más que el tope: si viene, es que hay corte. Es la forma barata de
    # saberlo sin un COUNT sobre el catálogo entero en cada tecla.
    found     = params[:q].present? ? Client.search(params[:q]).limit(Client::SEARCH_LIMIT + 1).to_a : []
    truncated = found.size > Client::SEARCH_LIMIT
    clients   = found.first(Client::SEARCH_LIMIT)
    order_id = ParamSanitizing.id(params[:order_id])
    order = current_user.orders.find_by(id: order_id)
    # Al editar el encabezado viene `order_id`. Si ya no existe (se descartó, o
    # "Obtener información" o "Cerrar rueda" borraron la cotización), las
    # sugerencias se armaban como para un registro nuevo: apuntaban al paso 1
    # de un PEDIDO y al guardar nacía una venta (15ª auditoría). El aviso va
    # dentro del panel, como en el buscador de producto (`order_gone`).
    if params[:order_id].present? && order.nil? && !Order.exists?(id: order_id)
      return render partial: "orders/order_gone", layout: false
    end
    # `truncated` va en los locals, no como ivar: el partial lo lee con
    # `local_assigns`, así que una ivar no le llega y el aviso no se pinta
    # nunca — el corte volvía a ser silencioso sin que nada fallara (8ª aud.).
    render partial: "client_options",
           locals: { clients: clients, order: order, truncated: truncated, document: document_param }, layout: false
  end

  def create
    @order = build_order
    if @order.save
      redirect_to @order, notice: (@order.generic? ? "Cotización iniciada. Continúa con el detalle."
                                                   : "Encabezado guardado. Continúa con el detalle.")
    else
      @client = @order.client
      @cfdi_uses = CfdiUse.order(:code)
      flash.now[:alert] = "Revisa los datos obligatorios del encabezado."
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @order = accessible_orders.find(params[:id])
  end

  # Cancelar la captura: descarta el pedido (solo si aún es editable). El
  # equipo-servidor puede descartar un borrador AJENO — ver
  # `with_locked_writable_order`.
  def destroy
    with_locked_writable_order(params[:id]) do |order|
      # La pantalla vieja de un pedido ya transmitido conserva el botón: sin
      # esta rama, el destroy se omitía en silencio y el flash confirmaba un
      # descarte que no ocurrió — el capturista creía cancelada una venta que
      # el ERP va a surtir (6ª auditoría, ALTA).
      if !order.editable?
        redirect_to order_path(order), alert: "Este pedido ya se transmitió al ERP y no se puede descartar aquí."
      else
        # `discard!` y no `destroy`: con una promoción aplicada, el candado de
        # las partidas abortaba el borrado y el flash de abajo confirmaba un
        # descarte que no ocurría (ver Order#discard!).
        order.discard!
        # Queda rastro de quién resolvió un borrador que no era suyo: el
        # capturista no se entera por ningún lado, y en la revisión posterior
        # "¿quién borró esto?" no tiene otra respuesta.
        log_resolved_draft(order, "descartado") unless order.user_id == current_user.id
        redirect_to root_path, notice: order.document_text(:discarded)
      end
    end
  end

  # Editar el encabezado del MISMO pedido (conserva las partidas). Puede cambiar
  # el cliente desde el buscador (recarga sobre el mismo pedido).
  def edit
    @order = current_user.orders.find(params[:id])
    return redirect_to @order, alert: ORDER_TRANSMITTED_MESSAGE unless @order.editable?

    if params[:client_key].present?
      new_client = client_from_key(params[:client_key])
      if new_client && new_client != @order.client
        @order.client = new_client
        # Los perfiles del encabezado eran del cliente anterior: se resetean.
        @order.client_tax_profile = @order.client_branch = @order.client_receipt_profile = @order.cfdi_use = nil
      end
    end

    @client    = @order.client
    @cfdi_uses = CfdiUse.order(:code)
    # Sin cliente (cotización genérica) no hay de dónde sacar defaults.
    apply_header_defaults if @client
    render :new
  end

  def update
    @order = current_user.orders.find(params[:id])
    return redirect_to @order, alert: ORDER_TRANSMITTED_MESSAGE unless @order.editable?

    if @order.update(order_params)
      redirect_to @order, notice: (@order.generic? ? "La cotización ahora es de cliente genérico." : "Encabezado actualizado.")
    else
      @client    = @order.client
      @cfdi_uses = CfdiUse.order(:code)
      flash.now[:alert] = "Revisa los datos obligatorios del encabezado."
      render :new, status: :unprocessable_entity
    end
  end

  # Sugerencias del buscador de producto (código FECEGO/proveedor, nombre,
  # modelo, número de parte), acotadas al universo del capturista (los
  # productos de sus proveedores/marcas asignados en la rueda).
  def product_options
    @order = current_user.orders.find(params[:id])
    universe = current_user.product_universe(active_round)
    found = params[:q].present? ?
      universe.search(params[:q]).includes(:price, :price_override).limit(Product::SEARCH_LIMIT + 1).to_a : []
    truncated = found.size > Product::SEARCH_LIMIT
    @products = found.first(Product::SEARCH_LIMIT)
    no_membership = current_user.business_round_people.where(business_round: active_round).none?
    render partial: "product_options",
           locals: { order: @order, products: @products, no_membership: no_membership,
                     truncated: truncated,
                     blocked_by: @order.promotions_blocking(@products) }, layout: false
  end

  # Guarda observaciones (auto-save silencioso). Transmitido con la pantalla
  # abierta, `ensure_editable` regresa a la captura con el aviso: el `head
  # :forbidden` de antes revertía el campo sin decir por qué y lo dejaba
  # editable, igual que la 16ª encontró en partidas y promociones (17ª).
  def observations
    @order = current_user.orders.find(params[:id])
    return ensure_editable unless @order.editable?

    @order.update(observations: params[:observations])
    head :no_content
  end

  # Finaliza la captura (folio local) y va al resumen (paso 3).
  def capture
    with_locked_writable_order(params[:id]) do |order|
      @order = order
      next redirect_to(@order, alert: ORDER_TRANSMITTED_MESSAGE) unless @order.editable?

      resolving = @order.user_id != current_user.id

      if @order.capture!
        log_resolved_draft(@order, "guardado") if resolving
        redirect_to summary_order_path(@order)
      else
        # Un borrador vacío no se puede guardar, y qué hacer con él depende de
        # quién lo está viendo:
        #
        # - el capturista agrega un producto ("guardar el pedido" y no
        #   "finalizar": ningún control dice "finalizar" desde que el botón
        #   pasó a "Guardar", y un mensaje que nombra una acción que no está a
        #   la vista no se puede seguir, 8ª auditoría);
        # - el equipo-servidor NO puede agregar productos a un pedido ajeno,
        #   así que mandarlo a hacerlo es un callejón sin salida. Su salida es
        #   descartarlo.
        redirect_to @order, alert: (resolving ?
          "Este pedido no tiene productos, así que no se puede guardar. Descártalo para que deje de bloquear las operaciones del panel." :
          "Agrega al menos un producto antes de guardar #{@order.document_phrase}.")
      end
    end
  end

  # Paso 3: resumen con opciones (PDF / correo, solo en el pedido).
  def summary
    @order = accessible_orders.find(params[:id])
  end

  # Descarga del PDF del pedido. Solo pedidos: la cotización no lleva PDF
  # (decisión del usuario 2026-10-27), así que su id aquí es un 404.
  def pdf
    @order = accessible_orders.sale.find(params[:id])
    send_data Pdf::OrderGenerator.new(@order).render,
              filename: "pedido-#{@order.folio}.pdf", type: "application/pdf", disposition: "attachment"
  end

  private

  # Toma el pedido con candado de fila y vuelve a comprobar el permiso con la
  # fila FRESCA antes de escribir. Entre que la pantalla lo leyó y la
  # escritura, otro equipo pudo guardarlo o descartarlo: el equipo-servidor que
  # descartaba un borrador en el mismo instante en que su capturista lo
  # guardaba borraba un pedido ya capturado —con folio y listo para
  # transmitir—, y nadie se enteraba (11ª auditoría).
  #
  # `with_lock` relee la fila con FOR UPDATE: si ya no existe, RecordNotFound
  # (lo mismo que un id que nunca existió); si dejó de ser un borrador que el
  # servidor puede resolver, no se toca y se dice por qué. Y quien llegue
  # después espera al candado y ve el estado ya resuelto.
  #
  # El pedido se toma de lo que el usuario puede LEER (`accessible_orders`) y
  # no de un buscador de "escribibles" fuera del candado: con la pantalla de un
  # borrador ajeno abierta un rato, si el capturista lo guardaba, el servidor
  # recibía "No encontramos esa pantalla" en vez del aviso — que solo salía en
  # la ventana de milisegundos dentro del candado (12ª auditoría). El permiso
  # se decide adentro, con la fila fresca, igual para los dos casos.
  #
  # Una cotización ajena no es "un borrador que ya se guardó": el servidor no
  # resuelve cotizaciones (no bloquean nada), y el aviso de la carrera le
  # decía algo falso — que la guardaron, con la cotización todavía en
  # borrador (15ª auditoría). Solo llega aquí con una petición armada a mano.
  def with_locked_writable_order(id)
    order = accessible_orders.find(id)
    order.with_lock do
      if order.user_id == current_user.id || can_resolve_draft?(order)
        yield order
      elsif order.estimate?
        redirect_to order_path(order),
                    alert: "Las cotizaciones las guarda o descarta su capturista; el equipo del servidor " \
                           "solo las consulta. No se cambió nada."
      else
        redirect_to order_path(order),
                    alert: "Este pedido ya no es un borrador: lo guardaron desde otro equipo. No se cambió nada."
      end
    end
  end

  # Rastro de la resolución de un borrador ajeno. Va al log y no a la BD: es
  # información de auditoría para el equipo-servidor, no dato del pedido.
  def log_resolved_draft(order, action)
    # El id y no `folio`: un borrador todavía no tiene folio, y `folio` devuelve
    # el texto "(borrador)" — que en el log no identifica NADA cuando hay varios
    # abandonados, que es justo el caso que esta función existe para rastrear.
    # Al guardarlo sí hay folio, porque `capture!` lo asigna antes.
    identifier = order.local_folio.presence || "id #{order.id}"
    Rails.logger.warn("[pedidos] #{current_user.username} (server) #{action} el borrador " \
                      "#{identifier} de #{order.user.username}")
  end

  # El buscador manda "CLAVE — Nombre comercial": se toma la clave y, si no
  # existe tal cual, se busca por texto (mismo criterio en el paso 1 y al
  # editar el encabezado).
  def client_from_key(value)
    key = value.to_s.strip.split(/\s[–-]\s/).first.to_s.strip
    Client.find_by(erp_client_key: key) || Client.search(key).first
  end

  def require_capturista
    return if current_user.capturista?

    redirect_to root_path, alert: "Capturar pedidos y cotizaciones es de los capturistas: " \
                                  "el equipo del servidor los consulta."
  end

  def apply_header_defaults
    # El tipo default depende de lo que el cliente tenga en el ERP: sin datos
    # fiscales no hay Factura; sin remisiones no hay Remisión (la vista oculta
    # la opción no disponible).
    @order.kind ||= @client.tax_profiles.any? ? "invoice" : "remission"
    # El ERP no marca un perfil fiscal/remisión "principal": si el cliente tiene
    # varios, NO preseleccionamos ninguno (evita elegir el RFC equivocado en
    # silencio); el capturista lo escoge. Con uno solo, sí lo preseleccionamos.
    @order.client_tax_profile     ||= @client.tax_profiles.first     if @client.tax_profiles.count == 1
    @order.client_receipt_profile ||= @client.receipt_profiles.first if @client.receipt_profiles.count == 1
    # Sucursal sí tiene default real en el ERP (sucursal = 1).
    @order.client_branch          ||= @client.branches.find_by(is_default: true) || @client.branches.first
    @order.cfdi_use               ||= @order.client_tax_profile&.default_cfdi_use
  end

  # "estimate" si se pidió una cotización; cualquier otra cosa es un pedido.
  # Vale para `?document=` (entrada y sugerencias) y para `order[document]`.
  def document_param(value = params[:document])
    value == "estimate" ? "estimate" : "sale"
  end

  def build_order
    Order.new(order_params).tap do |o|
      o.user           = current_user
      o.business_round = active_round
      o.status         = "draft"
      # SOLO al crear: el tipo se fija aquí y no vuelve a aceptarse (ver
      # Order#document_is_fixed). Con `kind`, pasa por el saneo de abajo.
      o.document       = document_param(params.dig(:order, :document))
    end
  end

  def order_params
    permitted = params.require(:order).permit(
      :client_id, :kind, :client_tax_profile_id, :cfdi_use_id,
      :client_receipt_profile_id, :client_branch_id, :dividir_facturas
    )
    # `kind` es un enum: asignarle un valor fuera del catálogo levanta
    # ArgumentError ANTES de cualquier validación, así que no hay forma de
    # atajarlo en el modelo. El campo viaja como radio (o hidden cuando el
    # cliente solo admite un tipo), o sea que basta con cambiarlo en el
    # inspector para tumbar la pantalla con un 500 — y en el modo con que corre
    # la laptop, ese 500 es la página de depuración de Rails para toda la LAN.
    # En blanco lo recoge `validates :kind, presence: true` y sale por el
    # camino normal de "revisa los datos obligatorios".
    permitted[:kind] = nil if permitted.key?(:kind) && !Order.kinds.key?(permitted[:kind])
    permitted
  end
end
