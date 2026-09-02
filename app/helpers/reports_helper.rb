module ReportsHelper
  # Cantidad de piezas como se lee en un reporte: sin ceros insignificantes.
  # La columna es `decimal(14,3)` porque hay producto a granel, pero casi todo
  # se vende por pieza entera y "2.000" en una tabla se lee como error.
  # El cero se muestra como raya: en la columna de regalos, "0" en cada renglón
  # es ruido que compite con las cantidades que sí importan.
  def report_quantity(value)
    return "—" if value.nil? || value.to_d.zero?

    number_with_precision(value, precision: 3, strip_insignificant_zeros: true, delimiter: ",")
  end
end
