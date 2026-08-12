class HomeController < ApplicationController
  # El menú usa el shell oscuro full-bleed (mismo que el login).
  layout "auth"

  def index
    # El contexto (rueda activa, proveedor activo, proveedores disponibles) lo
    # proveen los helpers de ApplicationController. Para el servidor, además el
    # estado del sync.
    return unless current_user&.can_see_all_orders?

    # Autorrecuperación sin reiniciar: una corrida cuyo proceso murió (Ctrl-C
    # o kill a un rake, apagón) quedaba `running` para siempre — captura
    # pausada, panel girando y reiniciar el servicio como única salida que
    # ninguna pantalla decía. Al volver al menú se barre lo muerto; las
    # corridas con proceso vivo se respetan (pid).
    SyncRun.recover_orphaned!

    @setting   = Setting.instance
    @sync_down = SyncRun.latest("down")
    @sync_up   = SyncRun.latest("up")
  end
end
