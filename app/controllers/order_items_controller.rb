class OrderItemsController < ApplicationController
  before_action :set_order
  before_action :ensure_editable

  # Agrega un producto como partida (snapshot). Responde con Turbo Stream.
  def create
    product = Product.find(params[:product_id])
    @order.order_items.create!(
      product.to_order_item_attributes.merge(
        position: @order.next_item_position, quantity: 1, discount_percent: 0
      )
    )
    render turbo_stream: [*detail_streams, clear_search_stream]
  end

  def update
    @order.order_items.find(params[:id]).update(item_params)
    render turbo_stream: detail_streams
  end

  def destroy
    @order.order_items.find(params[:id]).destroy
    render turbo_stream: detail_streams
  end

  private

  def set_order
    @order = current_user.orders.find(params[:order_id])
  end

  # Un pedido transmitido al ERP ya no se puede editar.
  def ensure_editable
    return if @order.editable?

    head :forbidden
  end

  def item_params
    params.require(:order_item).permit(:quantity, :discount_percent)
  end

  def detail_streams
    [
      turbo_stream.replace("order-detail", partial: "orders/items_table", locals: { order: @order }),
      turbo_stream.replace("order-totals", partial: "orders/totals", locals: { order: @order })
    ]
  end

  def clear_search_stream
    turbo_stream.update("product-search-results", "")
  end
end
