class OrderItemsController < ApplicationController
  # Todo aquí es escritura, así que la pausa aplica a las tres acciones.
  before_action :pause_writes_during_sync
  before_action :set_order
  before_action :ensure_editable

  # Agrega un producto como partida (snapshot). Responde con Turbo Stream.
  # El find va scopeado al universo del capturista (sus proveedores/marcas):
  # un product_id fuera del universo → 404, aunque el POST venga forjado.
  def create
    product = current_user.product_universe(active_round).find(params[:product_id])

    # El genérico (999999) se captura con descripción, parte y precio
    # propios: el primer POST (el clic en la opción del buscador, sin datos)
    # responde el mini-formulario en el panel de resultados; el segundo, ya
    # con `:generic`, crea la partida.
    # respond_to?(:permit) y no blank?: un `generic` forjado escalar ("1")
    # pasaba el blank? y reventaba en el permit con un 500 sin mensaje —
    # tratarlo como ausente lo manda al mini-formulario (6ª auditoría).
    if product.generic? && !params[:generic].respond_to?(:permit)
      return render turbo_stream: turbo_stream.update(
        "product-search-results", partial: "orders/generic_item_form",
        locals: { order: @order, product: product, item: nil }
      )
    end
    # La cantidad inicial arranca en el empaque mínimo de venta (si el producto
    # vende por múltiplos); 1 en caso contrario. Se exige POSITIVO y no
    # `presence`: sobre un decimal cero `presence` devuelve 0.0, no nil, así que
    # un producto con empaque 0 en el ERP nacía en cantidad 0, la validación lo
    # rechazaba y quedaba invendible sin remedio offline. Mismo criterio que
    # `OrderItem#quantity_in_package_multiples`, que ya ignora el empaque ≤ 0.
    package_size = product.min_sale_quantity
    # Se mira ANTES de agregar: después, el producto ya está dos veces.
    previous_position = @order.order_items.where(product_id: product.id).minimum(:position)
    item = @order.order_items.build(
      product.to_order_item_attributes.merge(
        position: @order.next_item_position, discount_percent: 0,
        quantity: (package_size&.positive? ? package_size : 1),
        **generic_overrides(product)
      )
    )
    if item.save
      # El buscador ya marcaba el producto como repetido, pero la lista se
      # cierra al elegir: sin este aviso, un duplicado agregado de prisa se
      # perdía entre 45 renglones y el ERP surtía doble. No se bloquea —el
      # mismo producto con distinto descuento es legítimo—, se hace visible.
      # El genérico no avisa: varias partidas "fuera de catálogo" son el uso
      # normal, no un descuido.
      streams = [ *detail_streams, clear_search_stream, scroll_to_stream(item) ]
      if previous_position && !product.generic?
        streams << turbo_stream.replace("flash", partial: "shared/flash",
                                                 locals: { alert: duplicate_message(item, previous_position) })
      end
      render turbo_stream: streams
    else
      # P.ej. producto sin precio: avisa sin agregar la partida. El genérico
      # re-muestra su formulario con lo tecleado, para corregir sin reescribir.
      form_stream = if item.generic?
        turbo_stream.update("product-search-results", partial: "orders/generic_item_form",
                            locals: { order: @order, product: product, item: item })
      else
        clear_search_stream
      end
      render turbo_stream: [
        form_stream,
        turbo_stream.replace("flash", partial: "shared/flash",
                                      locals: { alert: item.errors.full_messages.to_sentence })
      ]
    end
  end

  def update
    item = @order.order_items.find(params[:id])
    if item.update(item_params_for(item))
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
    # Quitar una partida intermedia dejaba huecos en el consecutivo.
    @order.renumber_items!
    # El botón que abrió el modal se fue con su fila, así que el foco caía al
    # <body> y había que retabular desde el inicio en cada baja. Va al buscador,
    # que es la acción natural siguiente.
    render turbo_stream: [
      *detail_streams,
      turbo_stream.replace("focus-director", partial: "orders/focus_director",
                                             locals: { selector: "#product-search input" })
    ]
  end

  private

  def duplicate_message(item, previous_position)
    "\"#{item.description}\" ya estaba en la partida #{previous_position}; " \
      "ahora está también en la #{item.position}. Si fue por error, quita una."
  end

  def set_order
    @order = current_user.orders.find(params[:order_id])
  end

  # Un pedido transmitido al ERP ya no se puede editar.
  def ensure_editable
    return if @order.editable?

    head :forbidden
  end

  # Candado por partida: descripción, no. de parte y precio solo se editan en
  # el genérico — en un producto de catálogo son snapshot del ERP y un PATCH
  # forjado no debe poder reescribirlos.
  def item_params_for(item)
    allowed = [ :quantity, :discount_percent ]
    allowed += [ :description, :part_number, :unit_price ] if item.generic?
    params.require(:order_item).permit(*allowed)
  end

  # Los tres campos capturados a mano del genérico, al crear. `require`: si
  # el POST llegó aquí es el segundo paso del mini-formulario.
  def generic_overrides(product)
    return {} unless product.generic?

    params.require(:generic).permit(:description, :part_number, :unit_price).to_h.symbolize_keys
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

  # Nodo efímero (ver scroll_to_controller): tras el morph, desliza la vista
  # hasta la fila recién agregada. Va DESPUÉS del repintado de la tabla en la
  # lista de streams, para que la fila ya exista cuando el controller conecte.
  def scroll_to_stream(item)
    turbo_stream.append("order-detail",
                        helpers.tag.div(nil, data: { controller: "scroll-to",
                                                     scroll_to_anchor_value: helpers.dom_id(item) }))
  end
end
