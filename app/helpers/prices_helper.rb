module PricesHelper
  # Segundo renglón de las tarjetas de la revisión de precios: un DATO, como el
  # importe en las del reporte de pedidos — no una instrucción (decisión del
  # usuario 2026-10-09).

  # "2,900 suben · 406 bajan"; sin el lado que venga en cero.
  def price_directions_label(counts)
    parts = []
    parts << "#{counts[:up].to_fs(:delimited)} #{counts[:up] == 1 ? 'sube' : 'suben'}" if counts[:up].positive?
    parts << "#{counts[:down].to_fs(:delimited)} #{counts[:down] == 1 ? 'baja' : 'bajan'}" if counts[:down].positive?
    parts.any? ? parts.join(" · ") : "Ninguno"
  end

  # Aviso de los borradores con partidas al precio anterior, dicho para quien
  # puede actuar: a qué capturista avisarle y de qué cliente es el pedido (el
  # servidor no puede editar borradores ajenos). Hasta 3 nombres; el resto,
  # "y N más".
  def stale_drafts_sentence(drafts)
    who = drafts.first(3).map { |d| "#{d.capturista} (#{d.client})" }
    who << "#{drafts.size - 3} más" if drafts.size > 3
    locked = drafts.sum(&:locked)
    [ "#{drafts.size == 1 ? 'Hay 1 pedido en borrador' : "Hay #{drafts.size} pedidos en borrador"} con partidas " \
      "al precio anterior: #{SpanishText.list(who)}.",
      "No cambian solas: pide a cada capturista que las quite y las agregue otra vez" +
        (locked.positive? ? "; las que tienen promoción aplicada, después de quitar la promoción." : ".") ].join(" ")
  end

  # Singular y plural de cada tipo de motivo: `pluralize` es del inglés.
  REJECTED_KIND_LABELS = {
    no_price:      [ "sin precio", "sin precio" ],
    invalid_price: [ "precio inválido", "precios inválidos" ],
    invalid_code:  [ "código inválido", "códigos inválidos" ],
    not_in_round:  [ "fuera de la rueda", "fuera de la rueda" ],
    conflict:      [ "repetido con otro precio", "repetidos con otro precio" ],
    generic:       [ "del 999999", "del 999999" ]
  }.freeze

  # "3 fuera de la rueda · 17 sin precio": los dos motivos más frecuentes, y
  # el resto como "· N más" para que el renglón quepa en la tarjeta.
  def rejected_kinds_label(kinds)
    return "Ninguno" if kinds.empty?

    shown = kinds.first(2).map do |kind, n|
      singular, plural = REJECTED_KIND_LABELS.fetch(kind)
      "#{n.to_fs(:delimited)} #{n == 1 ? singular : plural}"
    end
    rest = kinds.drop(2).sum { |_, n| n }
    shown << "#{rest.to_fs(:delimited)} más" if rest.positive?
    shown.join(" · ")
  end
end
