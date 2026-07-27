class ReportsController < ApplicationController
  include Pagy::Backend

  # Hub de "Reportes de venta": muestra las opciones de reporte.
  layout "auth"

  def index; end

  # Reporte de pedidos capturados. Un capturista ve solo los suyos; el
  # equipo-servidor ve todos (para transmitirlos al ERP). Paginado: en un
  # evento grande la lista completa se vuelve pesada para la tablet.
  def captured_orders
    scope = current_user.can_see_all_orders? ? Order.all : current_user.orders
    @pagy, @orders = pagy(scope.includes(:client, :user, :order_items).order(created_at: :desc),
                          limit: 25)
    @all_scope = current_user.can_see_all_orders?
  end
end
