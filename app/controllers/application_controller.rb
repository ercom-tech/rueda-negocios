class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login
  before_action :require_current_session
  before_action :require_round_for_capturista

  helper_method :current_user, :logged_in?, :active_round, :available_suppliers,
                :current_supplier, :available_brands, :current_brand, :can_edit_order?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # Un pedido lo edita solo su capturista (y mientras no esté transmitido).
  # El rol server puede VER cualquier pedido, pero no editarlo.
  def can_edit_order?(order)
    order.editable? && order.user_id == current_user&.id
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

  # Restringe una acción al rol server (operador del sync).
  def require_server
    return if current_user&.can_see_all_orders?

    redirect_to root_path, alert: "Esta sección es solo para el equipo servidor."
  end
end
