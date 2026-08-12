class OrdersController < ApplicationController
  layout "auth"

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
    @order = Order.new(client: @client)
    apply_header_defaults if @client
  end

  # Sugerencias del autocompletado (clave o nombre).
  def client_options
    @clients = params[:q].present? ? Client.search(params[:q]).limit(10) : Client.none
    order = current_user.orders.find_by(id: params[:order_id])
    render partial: "client_options", locals: { clients: @clients, order: order }, layout: false
  end

  def create
    @order = build_order
    if @order.save
      redirect_to @order, notice: "Encabezado guardado. Continúa con el detalle."
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

  # Cancelar la captura: descarta el pedido (solo si aún es editable).
  def destroy
    order = current_user.orders.find(params[:id])
    order.destroy if order.editable?
    redirect_to root_path, notice: "Pedido descartado."
  end

  # Editar el encabezado del MISMO pedido (conserva las partidas). Puede cambiar
  # el cliente desde el buscador (recarga sobre el mismo pedido).
  def edit
    @order = current_user.orders.find(params[:id])
    return redirect_to @order, alert: "Un pedido transmitido no se puede editar." unless @order.editable?

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
    apply_header_defaults
    render :new
  end

  def update
    @order = current_user.orders.find(params[:id])
    return redirect_to @order, alert: "Un pedido transmitido no se puede editar." unless @order.editable?

    if @order.update(order_params)
      redirect_to @order, notice: "Encabezado actualizado."
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
    @products = params[:q].present? ? universe.search(params[:q]).includes(:price).limit(10) : Product.none
    no_membership = current_user.business_round_people.where(business_round: active_round).none?
    render partial: "product_options",
           locals: { order: @order, products: @products, no_membership: no_membership }, layout: false
  end

  # Guarda observaciones (auto-save silencioso).
  def observations
    order = current_user.orders.find(params[:id])
    return head(:forbidden) unless order.editable?

    order.update(observations: params[:observations])
    head :no_content
  end

  # Finaliza la captura (folio local) y va al resumen (paso 3).
  def capture
    @order = current_user.orders.find(params[:id])
    return redirect_to @order, alert: "Un pedido transmitido no se puede editar." unless @order.editable?

    if @order.capture!
      redirect_to summary_order_path(@order)
    else
      redirect_to @order, alert: "Agrega al menos un producto antes de finalizar."
    end
  end

  # Paso 3: resumen con opciones (PDF / correo).
  def summary
    @order = accessible_orders.find(params[:id])
  end

  # Descarga del PDF del pedido.
  def pdf
    @order = accessible_orders.find(params[:id])
    send_data Pdf::OrderGenerator.new(@order).render,
              filename: "pedido-#{@order.folio}.pdf", type: "application/pdf", disposition: "attachment"
  end

  private

  # El buscador manda "CLAVE — Nombre comercial": se toma la clave y, si no
  # existe tal cual, se busca por texto (mismo criterio en el paso 1 y al
  # editar el encabezado).
  def client_from_key(value)
    key = value.to_s.strip.split(/\s[–-]\s/).first.to_s.strip
    Client.find_by(erp_client_key: key) || Client.search(key).first
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

  def build_order
    Order.new(order_params).tap do |o|
      o.user           = current_user
      o.business_round = active_round
      o.status         = "draft"
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
