module Promotions
  # El Cotizador de la captura (2026-10-09): para la partida en la que está
  # parado el capturista, cuánto quedaría la pieza —y la caja, si el ERP la
  # tiene— en cada escalón de su promoción. Es lectura pura: no aplica nada ni
  # mira el acumulado del pedido; contesta "si el cliente llega a tal monto,
  # esto le cuesta".
  #
  # El precio de partida es el de la PARTIDA (`unit_price`), no el del
  # catálogo: es lo que ese pedido cobra, incluido un precio cargado desde
  # archivo cuando la partida se agregó.
  class Quote
    # `gift`: el escalón trae regalo. Sin decirlo, FANDELI (≥$15,000 al 9% y
    # ≥$20,000 al 9% + regalo) se veía como un renglón repetido.
    Row = Data.define(:condition, :percent, :gift, :piece_price, :box_price, :promo_piece_price, :promo_box_price)

    attr_reader :item, :promotion

    def initialize(item)
      @item = item
      # `promotion_on` ya devuelve nil para un regalo; el genérico (999999) no
      # está en el universo de ninguna promoción.
      @promotion = item.promotion_on(item.order.captured_on)
    end

    def product = item.product
    def unit_price = item.unit_price

    # Piezas por caja de la ficha técnica, o nil. Una caja de 1 pieza no es
    # caja para el Cotizador: sus columnas repetirían las de la pieza (49 de
    # los productos con promoción de Oaxaca la traen así).
    def pieces_per_box
      pieces = product&.pieces_per_box
      pieces if pieces && pieces > 1
    end

    def boxes? = pieces_per_box.present?

    # La unidad de venta de la partida, como la trae el ERP ("PZA.", "CAJA",
    # "PQ10"…). El precio unitario es por ESA unidad y `pieces_per_box` cuenta
    # unidades de venta, no piezas sueltas (14ª auditoría): el anzuelo 941101
    # se vende por CAJA de 100 y su "caja" de la ficha es de 10 cajitas. Por
    # eso la pantalla solo dice "pieza" cuando la unidad lo es.
    def unit = item.unit.presence || product&.unit

    def by_piece? = unit.to_s.delete(".").strip.upcase == "PZA"

    # Un renglón por escalón que se puede alcanzar, en el mismo orden que la
    # escalera del modal de promoción (`Group#ladder`): los PC no se aplican,
    # así que cotizarlos sería prometer un precio que la captura no da.
    #
    # El porcentaje es el que la captura APLICARÍA: el override del producto
    # gana sobre el escalón, igual que en `Group#discount_for` — con FANAL el
    # escalón va en 0% y el código al 10 o 20.
    def rows
      return [] unless promotion

      override = promotion.override_for(product)
      Group.new(item.order, promotion).ladder.map do |tier|
        percent = override || tier.discount_percent
        Row.new(condition: tier.condition_label, percent:, gift: tier.gifts?,
                piece_price: unit_price.round(2),
                box_price: (boxes? ? (unit_price * pieces_per_box).round(2) : nil),
                promo_piece_price: discounted(unit_price, percent),
                promo_box_price: (boxes? ? discounted(unit_price * pieces_per_box, percent) : nil))
      end
    end

    private

    # Redondeo al final, como el total de una partida (cantidad × precio, y el
    # descuento sobre eso): la caja con promoción NO es la pieza ya redondeada
    # por las piezas, que con cajas de 500 se desviaría varios pesos.
    def discounted(amount, percent)
      (amount * (1 - percent / 100)).round(2)
    end
  end
end
