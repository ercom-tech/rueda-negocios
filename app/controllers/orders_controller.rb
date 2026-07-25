class OrdersController < ApplicationController
  layout "auth"

  # Paso 1 — encabezado. `client_key` carga al cliente (clave exacta o, si no,
  # el primer match por nombre).
  def new
    if params[:client_key].present?
      # El buscador puede traer "CLAVE - Nombre"; toma la clave (primer token).
      key = params[:client_key].to_s.strip.split(/\s[–-]\s/).first.to_s.strip
      @client = Client.find_by(erp_client_key: key) || client_search(key).first
    end
    @cfdi_uses = CfdiUse.order(:code)
    @order = Order.new(client: @client)
    apply_header_defaults if @client
  end

  # Sugerencias del autocompletado (clave o nombre).
  def client_options
    @clients = params[:q].present? ? client_search(params[:q]) : Client.none
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
    @order = current_user.orders.find(params[:id])
  end

  # Editar el encabezado del MISMO pedido (conserva las partidas). Puede cambiar
  # el cliente desde el buscador (recarga sobre el mismo pedido).
  def edit
    @order = current_user.orders.find(params[:id])
    return redirect_to @order, alert: "Un pedido transmitido no se puede editar." unless @order.editable?

    if params[:client_key].present?
      key   = params[:client_key].to_s.strip.split(/\s[–-]\s/).first.to_s.strip
      nuevo = Client.find_by(erp_client_key: key) || client_search(key).first
      if nuevo && nuevo != @order.client
        @order.client = nuevo
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
  # modelo, número de parte).
  def product_options
    @order = current_user.orders.find(params[:id])
    @products = params[:q].present? ? Product.search(params[:q]).includes(:price).limit(10) : Product.none
    render partial: "product_options", locals: { order: @order, products: @products }, layout: false
  end

  # Guarda observaciones (auto-save silencioso).
  def observations
    order = current_user.orders.find(params[:id])
    return head(:forbidden) unless order.editable?

    order.update(observations: params[:observations])
    head :no_content
  end

  # Finaliza la captura (folio local) y va al resumen (paso 3).
  def submit
    @order = current_user.orders.find(params[:id])
    return redirect_to @order, alert: "Un pedido transmitido no se puede editar." unless @order.editable?

    if @order.capture!
      redirect_to summary_order_path(@order)
    else
      redirect_to @order, alert: "Agrega al menos un producto antes de guardar."
    end
  end

  # Paso 3: resumen con opciones (PDF / correo / WhatsApp).
  def summary
    @order = current_user.orders.find(params[:id])
  end

  # Descarga del PDF del pedido.
  def pdf
    @order = current_user.orders.find(params[:id])
    send_data Pdf::OrderGenerator.new(@order).render,
              filename: "pedido-#{@order.folio}.pdf", type: "application/pdf", disposition: "attachment"
  end

  # (Diferido) envío por correo — offline no hay SMTP; se enviará al sincronizar.
  def send_email
    @order = current_user.orders.find(params[:id])
    email = params[:email].presence || @order.client.email
    redirect_to summary_order_path(@order),
                notice: "Correo programado para #{email} (se enviará al sincronizar)."
  end

  # (Stub) envío por WhatsApp.
  def send_whatsapp
    @order = current_user.orders.find(params[:id])
    redirect_to summary_order_path(@order), alert: "Envío por WhatsApp: próximamente."
  end

  private

  def client_search(query)
    q = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)
    return Client.none if q.blank?

    like   = "%#{q}%"
    prefix = "#{q}%"
    # Relevancia: primero los que EMPIEZAN con lo tecleado (en comercial o
    # nombre), luego alfabético por comercial (o nombre si no hay comercial).
    relevance = ActiveRecord::Base.sanitize_sql_array([
      "CASE WHEN commercial_name ILIKE :p OR name ILIKE :p THEN 0 ELSE 1 END, " \
      "COALESCE(NULLIF(commercial_name, ''), name)", { p: prefix }
    ])
    Client.includes(:salesperson)
          .where("name ILIKE :q OR commercial_name ILIKE :q OR erp_client_key ILIKE :q", q: like)
          .order(Arel.sql(relevance)).limit(10)
  end

  def apply_header_defaults
    @order.kind ||= "invoice"
    @order.client_tax_profile     ||= @client.tax_profiles.find_by(is_default: true) || @client.tax_profiles.first
    @order.client_branch          ||= @client.branches.find_by(is_default: true) || @client.branches.first
    @order.client_receipt_profile ||= @client.receipt_profiles.find_by(is_default: true) || @client.receipt_profiles.first
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
    params.require(:order).permit(
      :client_id, :kind, :client_tax_profile_id, :cfdi_use_id,
      :client_receipt_profile_id, :client_branch_id
    )
  end
end
