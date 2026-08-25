module PromotionsHelper
  # Los tres estados de la flama, en un solo lugar: la fila y el modal tienen
  # que contar la misma historia, y con el criterio repartido en las vistas
  # era fácil que una dijera "alcanzada" y la otra "todavía no".
  #
  #   :applied    ya está aplicada
  #   :available  alcanza un escalón: solo falta darle clic
  #   :offered    el producto está en promoción pero el pedido todavía no
  #               alcanza ningún escalón. (Una promoción fuera de vigencia NO
  #               llega aquí: `Group.for_order` filtra por `effective_on`, así
  #               que ni siquiera pinta flama.)
  def promotion_flame_state(group)
    return :applied   if group.applied?
    return :available if group.applicable?

    :offered
  end

  # Coral en los dos estados encendidos, el mismo del botón "Guardar" y del
  # Total (decisión del usuario 2026-08-24): es el color con el que este
  # proyecto marca la acción primaria y la culminación, y es lo que el ojo del
  # capturista ya busca en esa pantalla.
  #
  # Lo que los separa es la FORMA, no el tono — que además es lo que pedía la
  # 7ª auditoría (los tres estados se distinguían solo por color, y "aplicada"
  # y "no alcanzada" compartían silueta):
  #
  #   available  píldora coral rellena, con pulso   → invita
  #   applied    flama coral de trazo, sin fondo    → informa
  #   offered    trazo neutral-600                  → está ahí, aún no alcanza
  #
  # Blanco sobre coral da 4.69:1 y el coral sobre crema 4.04:1: los dos por
  # encima de lo que piden. El dorado se descartó de trazo (1.39:1 sobre
  # crema) y como superficie ya no hace falta.
  #
  # Solo el COLOR cambia entre estados. La forma (`rounded-full`) vive en la
  # base aunque el estado no tenga fondo: una transición anima el color pero
  # NO el `border-radius`, así que con la forma en el estado el botón se
  # volvía cuadrado de golpe mientras su fondo seguía desvaneciéndose — un
  # cuadro apagándose al bajar la cantidad y perder el escalón.
  #
  # El cambio de estado va SIN transición, y eso es deliberado: la píldora de
  # fondo es un nodo condicional que desaparece de golpe, así que animar el
  # color del ícono lo dejaba ~150 ms en blanco sobre crema (1.16:1) al pasar
  # de `available` a `applied` — la flama se borraba justo al cruzar un
  # escalón, que es la interacción más común de la captura. Instantáneo, el
  # ícono y su fondo cambian en el mismo frame. La transición se conserva solo
  # en `offered`, que no tiene fondo y cuyo hover va de neutral a coral sobre
  # crema: ahí ningún paso intermedio se lava (8ª auditoría).
  FLAME_CLASSES = {
    applied:   "text-brand-coral",
    available: "text-white",
    offered:   "text-neutral-600 transition-colors hover:text-brand-coral"
  }.freeze

  def promotion_flame_class(state)
    "relative inline-flex h-11 w-11 items-center justify-center rounded-full " \
      "#{FLAME_CLASSES.fetch(state)}"
  end

  # El fondo coral que late, como capa aparte y solo en `available`.
  #
  # `animate-pulse` de Tailwind va de opacidad 1 a .5, así que la píldora se
  # ve rosa pálida a mitad del ciclo — el latido se nota mucho, a cambio de que
  # el coral y el blanco del ícono se laven durante ese medio segundo.
  # Decisión del usuario (2026-08-24) tras probar una variante más discreta
  # (1 → .85): se queda el .5. Si alguien lo cambia, que sea por lo mismo.
  #
  # El costo, medido después (8ª auditoría) y dejado aquí para que la decisión
  # se tome con el número a la vista, no para revertirla:
  #
  #   opacidad   píldora    ícono/píldora   píldora/crema   (piden 3:1)
  #   1.0        #bd5343    4.69 ✓          4.04 ✓
  #   0.85       #c56a5a    3.76 ✓          3.24 ✓
  #   0.5        #d9a08f    2.24 ✗          1.93 ✗
  #
  # O sea: la mitad de cada ciclo la flama queda por debajo del mínimo de AA
  # para elementos gráficos. Si algún día se quiere el latido sin ese costo, la
  # salida NO es subir el piso —eso ya se descartó— sino dejar la píldora opaca
  # y latir un `ring` alrededor, que no toca el contraste del ícono.
  #
  # `animate-pulse` anima la opacidad del elemento que la lleva: puesta en el
  # botón, al quitarse la clase la opacidad saltaba de ~0.5 a 1 de un frame al
  # otro — un destello justo antes de apagarse. En una capa propia no queda
  # residuo: el nodo entero desaparece con la clase.
  def promotion_flame_backdrop_class
    "absolute inset-0 rounded-full bg-brand-coral shadow-sm " \
      "animate-pulse motion-reduce:animate-none"
  end

  # El rótulo nombra la promoción: con varias en un pedido, "ver promoción"
  # se anunciaba igual en todas las filas y no se sabía cuál se abría.
  def promotion_flame_label(group, state)
    case state
    when :applied   then "Promoción #{group.promotion.name}, aplicada — ver detalle"
    when :available then "Promoción #{group.promotion.name}, disponible — ver detalle"
    else "Promoción #{group.promotion.name} — ver qué falta"
    end
  end

  def promotion_dialog_id(promotion)
    "promotion-dialog-#{promotion.id}"
  end

  # Descuento como lo lee una persona: "12%", "7.85%" (BTICINO usa dos
  # decimales), nunca "12.00%".
  def promotion_percent(value)
    "#{number_with_precision(value, precision: 2, strip_insignificant_zeros: true)}%"
  end

  # Lo que se anuncia como descuento de un escalón: el porcentaje si todas las
  # partidas llevan el mismo, o los dos extremos si el override por producto
  # los separa. Nunca el del escalón a secas — con FANAL eso decía "0%".
  def promotion_percents(percents)
    return nil if percents.blank?
    return promotion_percent(percents.first) if percents.one?

    "#{promotion_percent(percents.first)} y #{promotion_percent(percents.last)}"
  end

  # Un regalo con nombre y cantidad: "1 × SKIL - ESMERILADORA 4-1/2\" 9004".
  # Con nombre SIEMPRE, también en los escalones que aún no se alcanzan: el
  # ícono solo decía que había regalo, y "te llevas un regalo" no vende nada
  # si no se sabe qué es.
  def promotion_gift_label(gift)
    quantity = number_with_precision(gift.quantity, strip_insignificant_zeros: true)
    "#{quantity} × #{gift.product.description}"
  end

  # El regalo dentro del gancho ("con $X más…"): se nombra cuando es uno
  # solo; con varios, la cuenta — la escalera de abajo los detalla, y meter
  # dos nombres largos del ERP en una frase la vuelve ilegible.
  def promotion_gifts_teaser(tier)
    gifts = tier.promotion_gifts.to_a
    return nil if gifts.empty?

    gifts.one? ? promotion_gift_label(gifts.first) : "#{gifts.size} regalos"
  end
end
