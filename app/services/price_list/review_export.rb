require "csv"

module PriceList
  # La revisión completa en CSV, renglón por renglón del archivo: lo que cambia,
  # lo que queda igual y lo que no se aplica con su motivo. Es lo que el
  # operador abre en Excel para corregir el archivo, por eso va en el orden y
  # con la línea del archivo original.
  module ReviewExport
    HEADERS = [ "Línea", "Código", "Descripción", "Precio actual", "Precio nuevo", "Variación", "Resultado" ].freeze

    module_function

    def csv(review)
      rows =
        review.changes.map { |c| change_row(c, review.large?(c) ? "Cambia (variación mayor a #{percent(review.threshold)})" : "Cambia") } +
        review.unchanged.map { |c| change_row(c, "Queda igual") } +
        review.rejected.map { |r| [ r.line, r.code_text, nil, nil, nil, nil, "No se aplica: #{r.reason}" ] }

      CSV.generate do |csv|
        csv << HEADERS
        rows.sort_by(&:first).each { |row| csv << row }
      end
    end

    def change_row(change, result)
      [ change.line, format("%06d", change.code), change.description,
        change.current_price&.to_s("F"), change.new_price.to_s("F"), variation(change), result ]
    end

    def percent(fraction) = "#{(fraction * 100).to_i}%"

    def variation(change)
      return if change.variation.nil?

      format("%+.1f%%", change.variation * 100)
    end
  end
end
