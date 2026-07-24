class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login

  helper_method :current_user, :logged_in?, :active_round, :available_suppliers, :current_supplier

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
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

  def require_login
    return if logged_in?

    redirect_to login_path, alert: "Inicia sesión para continuar."
  end
end
