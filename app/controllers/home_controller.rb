class HomeController < ApplicationController
  # El menú usa el shell oscuro full-bleed (mismo que el login).
  layout "auth"

  def index
    @active_round = BusinessRound.active.first
    # TODO: el "Proveedor" del capturista aún no está modelado (ver nota en el
    # chat / memory). Placeholder hasta definir la relación usuario→proveedor.
    @supplier_name = nil
  end
end
