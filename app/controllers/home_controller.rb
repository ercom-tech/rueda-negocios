class HomeController < ApplicationController
  # El menú usa el shell oscuro full-bleed (mismo que el login).
  layout "auth"

  def index
    # El contexto (rueda activa, proveedor activo, proveedores disponibles) lo
    # proveen los helpers de ApplicationController.
  end
end
