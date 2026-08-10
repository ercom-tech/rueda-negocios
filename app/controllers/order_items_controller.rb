class OrderItemsController < ApplicationController
  before_action :set_order
  before_action :ensure_editable

  # Agrega un producto como partida (snapshot). Responde con Turbo Stream.
  # El find va scopeado al universo del capturista (sus proveedores/marcas):
  # un product_id fuera del universo → 404, aunque el POST venga forjado.
  def create
    product = current_user.product_universe(active_round).find(params[:product_id])
    # La cantidad inicial arranca en el empaque mínimo de venta (si el
    # producto vende por múltiplos); 1 en caso contrario.
    item = @order.order_items.build(
      product.to_order_item_attributes.merge(
        position: @order.next_item_position, discount_percent: 0,
        quantity: product.min_sale_quantity.presence || 1
      )
    )
    if item.save
      render turbo_stream: [*detail_streams, clear_search_stream]
    else
      # P.ej. producto sin precio: avisa sin agregar la partida.
      render turbo_stream: [
        clear_search_stream,
        turbo_stream.replace("flash", partial: "shared/flash",
                                      locals: { alert: item.errors.full_messages.to_sentence })
      ]
    end
  end

  def update
    item = @order.order_items.find(params[:id])
    if item.update(item_params)
      render turbo_stream: detail_streams
    else
      # No revertir en silencio: repinta con el valor válido anterior y avisa
      # con el motivo real (cantidad ≤ 0, descuento sobre el máximo, etc.).
      render turbo_stream: [
        *detail_streams,
        turbo_stream.replace("flash", partial: "shared/flash",
                                      locals: { alert: item.errors.full_messages.to_sentence })
      ]
    end
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

  # Morph (no replace): actualiza la tabla en sitio emparejando nodos por id,
  # así el input al que el usuario acaba de brincar (Tab/clic) NO se destruye
  # y conserva el foco — con replace, el foco moría y las flechas siguientes
  # scrolleaban la página al primer renglón.
  def detail_streams
    [
      turbo_stream.replace("order-detail", method: :morph, partial: "orders/items_table", locals: { order: @order }),
      turbo_stream.replace("order-totals", method: :morph, partial: "orders/totals", locals: { order: @order }),
      # El buscador también: al llegar al tope de partidas (o al bajar de él
      # quitando una) cambia su estado deshabilitado sin recargar la página.
      turbo_stream.replace("product-search", method: :morph, partial: "orders/product_search", locals: { order: @order })
    ]
  end

  def clear_search_stream
    turbo_stream.update("product-search-results", "")
  end
end
