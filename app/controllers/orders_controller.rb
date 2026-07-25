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
    render partial: "client_options", locals: { clients: @clients }, layout: false
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
    order.update(observations: params[:observations])
    head :no_content
  end

  private

  def client_search(query)
    like = "%#{query.to_s.strip}%"
    Client.includes(:salesperson)
          .where("name ILIKE :q OR commercial_name ILIKE :q OR erp_client_key ILIKE :q", q: like)
          .order(:name).limit(10)
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
