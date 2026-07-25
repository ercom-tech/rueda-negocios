class ReportsController < ApplicationController
  # Hub de "Reportes de venta": muestra las opciones de reporte.
  layout "auth"

  def index; end

  # Reporte de pedidos capturados. Un capturista ve solo los suyos; el
  # equipo-servidor ve todos (para transmitirlos al ERP).
  def captured_orders
    scope = current_user.can_see_all_orders? ? Order.all : current_user.orders
    @orders = scope.includes(:client, :user).order(created_at: :desc)
    @all_scope = current_user.can_see_all_orders?
  end
end
