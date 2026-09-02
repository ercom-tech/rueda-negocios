module ReportsHelper
  # Estilo de los controles dentro de la barra dorada de filtros (combos,
  # botones de descarga). Estaba copiado carácter por carácter en las dos
  # vistas de reporte: si cambiara el alto o el anillo de foco, una se quedaba
  # atrás sin que nada lo delatara.
  def filter_control_class
    "flex h-[46px] items-center gap-2 rounded-full bg-black px-5 text-white " \
      "focus-within:ring-2 focus-within:ring-brand-gold"
  end

  # Encabezado ordenable de la tabla del reporte de pedidos.
  #
  # El enlace lleva `page: nil` a propósito: reordenar y quedarse en la página
  # 7 deja al usuario en medio de una lista que ya no es la que estaba viendo.
  # `aria-sort` es lo que le dice a un lector de pantalla cuál columna manda —
  # sin él, la flecha es información solo para quien la ve.
  # `extra` son clases del `<th>` — hoy solo `hidden lg:table-cell`, para las
  # columnas que se esconden en tablet. Existe para que las NUEVE columnas
  # pasen por aquí: cuando Hora y Vendedor se escribían a mano porque el helper
  # no las admitía, la lógica de `aria-sort` quedó duplicada y expresada de dos
  # formas distintas — el mismo patrón que las convenciones narran con
  # `back_link_class` (9ª auditoría).
  def sortable_header(column, label, sort:, base_params:, align: "left", extra: nil)
    url = url_for(base_params.merge(sort: column, dir: sort.next_dir_for(column), page: nil))
    aria = case sort.direction_for(column)
    when "asc"  then "ascending"
    when "desc" then "descending"
    else "none"
    end

    tag.th class: [ "px-4 py-3 text-#{align} font-semibold", extra ].compact.join(" "),
           aria: { sort: aria } do
      link_to url, class: sort_header_class(sort.active?(column)) do
        safe_join([ label, sort_caret(sort.direction_for(column)) ])
      end
    end
  end

  # La columna que ordena va en DORADO, no solo con flecha: el dorado es el
  # color de navegación del sitio y sobre el negro del `thead` se lee de un
  # golpe. Con la flecha sola había que buscarla entre nueve encabezados —y
  # peor, el `hover` teñía de dorado la columna bajo el cursor, así que a
  # simple vista parecía la activa.
  def sort_header_class(active)
    base = "inline-flex items-center gap-1"
    active ? "#{base} text-brand-gold" : "#{base} hover:text-brand-gold/70"
  end

  # Solo la columna activa muestra flecha. Un indicador tenue en las nueve
  # ensuciaría el encabezado sin decir nada — que la celda sea clicable ya se
  # comunica con el hover.
  def sort_caret(direction)
    return "".html_safe unless direction

    path = direction == "asc" ? "m4.5 15.75 7.5-7.5 7.5 7.5" : "m19.5 8.25-7.5 7.5-7.5-7.5"
    tag.svg(class: "h-4 w-4 shrink-0", fill: "none", viewBox: "0 0 24 24",
            stroke_width: "2", stroke: "currentColor", aria: { hidden: true }) do
      tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: path)
    end
  end

  # Cantidad de piezas como se lee en un reporte: sin ceros insignificantes.
  # La columna es `decimal(14,3)` porque hay producto a granel, pero el 97.6%
  # se vende por pieza entera (medido sobre `vta_pedido_detalle`, `baja=false`)
  # y "2.000" en una tabla se lee como error de captura.
  # El cero se muestra como raya: en la columna de regalos, "0" en cada renglón
  # es ruido que compite con las cantidades que sí importan.
  def report_quantity(value)
    return "—" if value.nil? || value.to_d.zero?

    number_with_precision(value, precision: 3, strip_insignificant_zeros: true, delimiter: ",")
  end
end
