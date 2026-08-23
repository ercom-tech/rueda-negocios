module Promotions
  # Una promoción vista DENTRO de un pedido: qué partidas participan, cuánto
  # llevan acumulado, qué escalón alcanzan y cómo se aplica o se quita.
  #
  # El nombre es literal: la promoción es del GRUPO de partidas, no de la
  # fila desde la que se abre el modal. Aplicarla toca todas las partidas del
  # pedido que están en su universo, y el acumulado que elige el escalón sale
  # de la suma de todas ellas — verificado contra el ERP (pedido RP0624: 8 de
  # sus 19 partidas sumaban $17,466.43 y las ocho salieron al 10%, mientras
  # las otras once llevaban sus propias promociones o ninguna).
  #
  # Al aplicarse, las partidas quedan CONGELADAS (decisión FECEGO
  # 2026-08-22): para editarlas hay que quitar la promoción, corregir y
  # volver a aplicarla si sigue calificando. No hay recálculo automático —
  # así un descuento nunca cambia ni desaparece sin que alguien lo pida.
  class Group
    # El regalo va con 100% de descuento: precio de lista, neto en cero
    # (decisión FECEGO 2026-08-22).
    #
    # El ERP hace otra cosa en SUS promociones: deja el regalo en $0.25 + IVA
    # = $0.29, con un descuento del 99.9x calculado desde el monto. Se
    # descartó imitarlo porque la columna de porcentaje solo guarda dos
    # decimales, así que la app derivaba un neto aproximado (entre $0.25 y
    # ~$0.31 según el precio) y el papel del cliente terminaba cobrando
    # centavos por algo que le prometieron regalado.
    #
    # El 100% no es un invento nuestro: el ERP ya tiene 729 partidas así, en
    # 459 pedidos, todas con total en $0.00. Y su validación de montos es por
    # fórmula, de modo que descuento = subtotal, IVA = 0 y total = 0 cuadran
    # solos.
    GIFT_DISCOUNT = 100

    attr_reader :order, :promotion

    # Regalos que el escalón prometía y no se pudieron agregar (sin precio en
    # el ERP, o cantidad que no cuadra con el empaque). Se llena en `apply!` y
    # el controlador lo dice en el flash: la escalera del modal los nombra, así
    # que el capturista ya se los prometió al cliente (7ª auditoría).
    attr_reader :missing_gifts

    def initialize(order, promotion)
      @order = order
      @promotion = promotion
      @missing_gifts = []
    end

    # Las promociones que tocan este pedido, una vez cada una, en el orden en
    # que aparecen sus partidas. Un pedido puede aplicar varias.
    def self.for_order(order)
      index_by_product(order).values.uniq.map { |promotion| new(order, promotion) }
    end

    # { product_id => Promotion } de las partidas de este pedido. Una sola
    # consulta para todas: preguntarlo partida por partida eran 45 consultas
    # idénticas en CADA repintado de la tabla (7ª auditoría). Lo consume
    # también la vista, para saber qué flama pintar en cada fila.
    def self.index_by_product(order)
      product_ids = order.order_items.reject(&:gift?).filter_map(&:product_id).uniq
      Promotion.index_by_product(product_ids, on: order.captured_on)
    end

    # Partidas del pedido que participan. Los regalos se excluyen: son
    # consecuencia de la promoción, no parte de lo que la detona — contarlos
    # inflaría el acumulado con su propio premio.
    def items
      @items ||= order.order_items.reject(&:gift?).select { |item| product_ids.include?(item.product_id) }
    end

    def gift_items
      @gift_items ||= order.order_items.select { |item| item.gift? && item.promotion_id == promotion.id }
    end

    # El acumulado que elige el escalón: importe BRUTO (cantidad × precio,
    # antes de descuento) si la promoción mide en MXN, piezas si mide en PZA.
    def accumulated
      @accumulated ||= if promotion.measured_in_money?
        items.sum(&:line_total)
      else
        items.sum(&:quantity)
      end
    end

    def tier
      @tier ||= promotion.tier_for(accumulated)
    end

    # El siguiente escalón hacia arriba — el gancho del modal ("con $2,534
    # más pasas de 10% a 12%"). nil si ya está en el tope.
    def next_tier
      @next_tier ||= promotion.promotion_tiers
                              .select { |t| t.supported? && t.quantity_from > accumulated }
                              .min_by(&:quantity_from)
    end

    def missing_for_next_tier
      return nil if next_tier.nil?

      next_tier.quantity_from - accumulated
    end

    def applied?
      items.any? { |item| item.promotion_id == promotion.id }
    end

    def effective?
      promotion.effective_on?(order.captured_on)
    end

    # Se puede aplicar: está vigente, hay partidas, y alcanzan un escalón.
    def applicable?
      effective? && items.any? && tier.present?
    end

    # Por qué NO se puede aplicar, en el lenguaje del capturista. nil si sí
    # se puede. El modal lo muestra en lugar del botón.
    def blocked_reason
      return nil if applicable?
      return "Esta promoción estuvo vigente del #{format_date(promotion.starts_on)} al " \
             "#{format_date(promotion.ends_on)}." unless effective?
      return "Este pedido no tiene productos de esta promoción." if items.empty?

      # Tres ramas, no una. La frase única ("no alcanzas el mínimo") se
      # disparaba SIEMPRE que ningún escalón cubriera, y en la rueda hay 24
      # transiciones con hueco de un peso entre rangos cerrados: con $14,999.48
      # recitaba que el mínimo son $10,000 — cinco mil por debajo de lo que ya
      # llevaba, contradiciendo al gancho de tres renglones arriba. Y sin
      # escalones aplicables salía rota ("y  es lo mínimo"). (7ª auditoría.)
      return "Esta promoción no trae escalones que se puedan aplicar. " \
             "Avísale al equipo del servidor." if ladder.empty?

      if next_tier
        "Llevas #{formatted_accumulated}. Te faltan " \
          "#{tier_amount(missing_for_next_tier)} para el descuento del " \
          "#{ActiveSupport::NumberHelper.number_to_rounded(next_tier.discount_percent, precision: 2, strip_insignificant_zeros: true)}%."
      else
        "Llevas #{formatted_accumulated} y no cae en ningún escalón de esta " \
          "promoción. Avísale al equipo del servidor."
      end
    end

    # --- Aplicar / quitar --------------------------------------------------

    # Congela las partidas del grupo con el descuento del escalón y agrega
    # los regalos. Idempotente: aplicarla dos veces deja lo mismo.
    def apply!
      return false unless applicable?

      @missing_gifts = []
      order.transaction do
        items.each { |item| apply_to(item) }
        rebuild_gifts!
      end
      reset_memo
      true
    end

    # Devuelve las partidas a manos del capturista: restaura el descuento que
    # tenía tecleado antes (decisión del usuario 2026-08-22) y retira los
    # regalos. Sin memoria previa vuelve a 0, que es como nacen las partidas.
    def unapply!
      # Sin esta guarda, quitar dos veces dejaba el descuento en 0: la primera
      # pasada restaura el manual y vacía la memoria, la segunda ya no
      # encuentra nada y aterriza en cero — con el flash afirmando que se
      # quitó una promoción que ya no estaba (7ª auditoría). Alcanzable con
      # dos pestañas, un reintento, o el modal recargándose asíncrono.
      return false unless applied?

      order.transaction do
        gift_items.each { |item| item.promotion_managed = true; item.destroy }
        # Solo las partidas de ESTA promoción: `items` son todas las del
        # universo, aplicadas o no, y tocar una que nunca se aplicó le borraba
        # al capturista el descuento que había tecleado.
        items.select { |item| item.promotion_id == promotion.id }.each { |item| release(item) }
        order.renumber_items!
      end
      reset_memo
      true
    end

    # --- Presentación ------------------------------------------------------

    # El descuento que le toca a una partida bajo el escalón vigente: el
    # override del producto si lo tiene, si no el del escalón.
    def discount_for(item)
      promotion.override_for(item.product) || tier&.discount_percent || 0
    end

    def formatted_accumulated
      tier_amount(accumulated)
    end

    def tier_amount(value)
      if promotion.measured_in_money?
        ActiveSupport::NumberHelper.number_to_currency(value)
      else
        pieces = ActiveSupport::NumberHelper.number_to_rounded(value, strip_insignificant_zeros: true)
        "#{pieces} #{value == 1 ? 'pieza' : 'piezas'}"
      end
    end

    # Los porcentajes que de verdad les tocan a las partidas del grupo bajo un
    # escalón dado, sin repetir. Es lo que la pantalla debe anunciar: leer
    # `tier.discount_percent` se salta el override por producto, y con FANAL
    # —escalón en 0%, 57 códigos al 10% y 20%— el modal anunciaba "0% de
    # descuento" sobre partidas que quedaban al 10 y al 20 (7ª auditoría).
    def percents_for(step = tier)
      return [] if step.nil?

      base = items.presence || promotion.promotion_products.includes(:product).map(&:product)
      base.map { |it| promotion.override_for(it.try(:product) || it) || step.discount_percent }
          .uniq.sort
    end

    # Los escalones que la pantalla muestra como escalera. Los no soportados
    # (PC, o un tipo nuevo del ERP) se quedan fuera: no se pueden alcanzar,
    # así que anunciarlos sería prometer algo que el botón no puede cumplir.
    def ladder
      promotion.promotion_tiers.select(&:supported?).sort_by(&:quantity_from)
    end

    private

    def product_ids
      @product_ids ||= promotion.promotion_products.pluck(:product_id).to_set
    end

    def apply_to(item)
      percent = discount_for(item)
      # La memoria del descuento manual se escribe UNA sola vez: si la
      # promoción ya está aplicada y se re-aplica (p. ej. tras agregar más
      # partidas), volver a copiarla guardaría el descuento de la promoción
      # como si fuera del capturista, y al quitarla se quedaría pegado.
      item.manual_discount_percent = item.discount_percent if item.promotion_id.nil?
      item.promotion = promotion
      item.promotion_tier = tier
      item.discount_percent = percent
      item.promotion_discount_percent = percent
      item.promotion_managed = true
      item.save!
    end

    def release(item)
      item.discount_percent = item.manual_discount_percent || 0
      item.manual_discount_percent = nil
      item.promotion = nil
      item.promotion_tier = nil
      item.promotion_discount_percent = nil
      item.promotion_managed = true
      item.save!
    end

    # Los regalos son del ESCALÓN: al cambiar de escalón, los del anterior se
    # van y entran los del nuevo. Se reconstruyen en vez de conciliarse
    # porque son a lo sumo dos renglones y la reconciliación parcial es donde
    # se cuelan los duplicados.
    def rebuild_gifts!
      gift_items.each(&:destroy)
      @gift_items = nil
      return if tier.nil?

      tier.promotion_gifts.includes(:product).each do |gift|
        create_gift(gift)
      end
      order.renumber_items!
    end

    def create_gift(gift)
      attributes = gift.product.to_order_item_attributes
      quantity   = gift.quantity
      price      = attributes[:unit_price]
      # Un regalo sin precio en el ERP no se puede valuar. Se omite en vez de
      # entrar en $0: una partida gratis que nadie configuró así es un
      # faltante que el ERP no puede explicar.
      if price.blank? || price <= 0 || quantity <= 0
        @missing_gifts << promotion_gift_name(gift)
        return
      end

      # `create` y no `create!`: la cantidad la dicta el ERP y puede no cuadrar
      # con el empaque mínimo del producto (`quantity_in_package_multiples`).
      # Con `create!` eso era una excepción sin rescate → pantalla de error del
      # sistema y promoción inaplicable, offline, sin decir por qué. Se cuenta
      # como los regalos sin precio y el capturista se entera por el flash.
      gift_item = order.order_items.create(
        attributes.merge(
          position: order.next_item_position,
          quantity: quantity,
          # Dictado y aplicado coinciden en 100: la promoción regala la
          # partida entera y así se cobra. (En los regalos del propio ERP
          # difieren — dicta 100 y aplica 99.9x — porque él sí deja los
          # centavos; ver GIFT_DISCOUNT.)
          discount_percent: GIFT_DISCOUNT,
          promotion_discount_percent: GIFT_DISCOUNT,
          gift: true,
          promotion: promotion,
          promotion_tier: tier,
          promotion_managed: true
        )
      )
      @missing_gifts << promotion_gift_name(gift) unless gift_item.persisted?
    end

    def promotion_gift_name(gift)
      quantity = ActiveSupport::NumberHelper.number_to_rounded(gift.quantity, strip_insignificant_zeros: true)
      "#{quantity} × #{gift.product.description}"
    end

    def format_date(date)
      I18n.l(date, format: "%d/%m/%Y") if date
    end

    def reset_memo
      @items = @gift_items = @accumulated = @tier = @next_tier = @product_ids = nil
      order.order_items.reset
    end
  end
end
