class PromotionsController < ApplicationController
  # Aplicar y quitar una promoción de la rueda sobre un pedido. Toda la regla
  # vive en `Promotions::Group`; aquí solo están el candado de acceso y el
  # repintado.
  # `show` es lectura: se puede ver el detalle de una promoción durante un
  # sync y en un pedido ya transmitido.
  before_action :pause_writes_during_sync, except: :show
  before_action :set_order
  before_action :ensure_editable, except: :show

  # Contenido del modal, dentro de su turbo-frame. Se pide cada vez que el
  # modal se abre: el cascarón es `data-turbo-permanent` (sobrevive al morph)
  # y por eso su contenido no puede venir renderizado de fábrica — se
  # quedaría congelado en el estado que tenía al pintarse la tabla.
  def show
    render partial: "orders/promotion_detail",
           locals: { order: @order, group: group_for(params[:id]) }
  end

  def create
    group = group_for(params[:promotion_id])

    if apply_safely(group)
      render turbo_stream: [ *detail_streams, flash_stream(notice: applied_message(group)) ]
    else
      # `blocked_reason` dice qué falta (vigencia vencida, mínimo no
      # alcanzado, ninguna partida): el capturista abrió el modal con el
      # botón habilitado y entre eso y el clic algo cambió — repintar sin
      # explicación se leería como que el botón no sirve.
      render turbo_stream: [ *detail_streams,
                             flash_stream(alert: @apply_error || group.blocked_reason) ]
    end
  end

  def destroy
    group = group_for(params[:id])
    count = group.items.count { |item| item.promotion_id == group.promotion.id }

    # `unapply!` devuelve false si ya no estaba aplicada. Afirmar que se quitó
    # algo que no estaba es la familia del ALTA de la 6ª auditoría — y aquí
    # además la segunda pasada borraba el descuento tecleado.
    unless group.unapply!
      return render turbo_stream: [
        *detail_streams,
        flash_stream(alert: "Esa promoción ya no estaba aplicada en este pedido. No se cambió nada.")
      ]
    end

    render turbo_stream: [
      *detail_streams,
      flash_stream(notice: "Se quitó la promoción \"#{group.promotion.name}\". " \
                           "#{count == 1 ? 'La partida vuelve a ser editable' : 'Las partidas vuelven a ser editables'}.")
    ]
  end

  private

  # Un dato del ERP que no cuadra con las validaciones locales (una cantidad
  # de regalo fuera del empaque mínimo, p. ej.) levantaba una excepción sin
  # rescate: pantalla de error del sistema, offline, sin decir por qué.
  def apply_safely(group)
    group.apply!
  rescue ActiveRecord::RecordInvalid => e
    @apply_error = e.record.errors.full_messages.to_sentence
    false
  end

  def group_for(promotion_id)
    Promotions::Group.new(@order, Promotion.find(promotion_id))
  end

  def applied_message(group)
    # El porcentaje sale de lo que se APLICA, no del primero de la lista: con
    # override por producto, `items.first` era una muestra y el mensaje decía
    # "10% en 2 partidas" con una al 20% — y al revés según el orden de
    # captura (7ª auditoría).
    percents = group.percents_for
    message = "Se aplicó la promoción \"#{group.promotion.name}\": " \
              "#{helpers.promotion_percents(percents)}"
    message += " según el producto" if percents.many?
    message += " en #{helpers.pluralize(group.items.size, 'partida')}. " \
               "#{group.items.size == 1 ? 'Quedó bloqueada' : 'Quedaron bloqueadas'}: " \
               "quita la promoción si necesitas cambiar algo."

    gifts = group.gift_items.size
    # El regalo entra como partida nueva al final del pedido: sin decirlo, el
    # capturista descubre un renglón que no capturó y no sabe de dónde salió.
    if gifts.positive?
      message += " Se #{gifts == 1 ? 'agregó' : 'agregaron'} " \
                 "#{helpers.pluralize(gifts, 'partida')} de regalo."
    end
    # Y si un regalo que la escalera prometía no se pudo agregar, se dice: el
    # capturista ya se lo ofreció al cliente.
    if group.missing_gifts.any?
      message += " No se pudo agregar #{group.missing_gifts.to_sentence}: " \
                 "avísale al equipo del servidor antes de finalizar."
    end
    message
  end

  def set_order
    @order = current_user.orders.find(params[:order_id])
  end

  def ensure_editable
    return if @order.editable?

    head :forbidden
  end

  # Los mismos tres nodos que repinta OrderItemsController: la tabla cambia
  # (descuentos, regalos, candados), los totales cambian, y el buscador
  # también — al aplicar una promoción, sus productos dejan de poder
  # agregarse hasta que se quite.
  def detail_streams
    [
      turbo_stream.replace("order-detail", method: :morph, partial: "orders/items_table", locals: { order: @order }),
      turbo_stream.replace("order-totals", method: :morph, partial: "orders/totals", locals: { order: @order }),
      turbo_stream.replace("product-search", method: :morph, partial: "orders/product_search", locals: { order: @order })
    ]
  end

  def flash_stream(notice: nil, alert: nil)
    turbo_stream.replace("flash", partial: "shared/flash", locals: { notice: notice, alert: alert }.compact)
  end
end
