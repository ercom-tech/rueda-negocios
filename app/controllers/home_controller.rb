class HomeController < ApplicationController
  # El menú usa el shell oscuro full-bleed (mismo que el login).
  layout "auth"

  def index
    # El contexto (rueda activa, proveedor activo, proveedores disponibles) lo
    # proveen los helpers de ApplicationController. Para el servidor, además el
    # estado del sync.
    return unless current_user&.can_see_all_orders?

    @setting   = Setting.instance
    @sync_down = SyncRun.latest("down")
    @sync_up   = SyncRun.latest("up")
  end
end
