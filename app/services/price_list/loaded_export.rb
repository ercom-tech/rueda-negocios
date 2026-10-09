require "csv"

module PriceList
  # Los precios cargados de la rueda activa, producto por producto, contra el
  # precio del ERP de HOY: el rastro de qué se cambió, con qué archivo, quién y
  # cuándo. La pantalla solo los cuenta por archivo.
  #
  # Un código que ya no está en el catálogo (lo quitó una obtención de
  # información posterior) sale igual, sin descripción: su precio sigue
  # cargado aunque hoy no aplique a nada.
  module LoadedExport
    HEADERS = [ "Código", "Descripción", "Precio del ERP", "Precio de rueda", "Variación",
                "Archivo", "Cargó", "Fecha" ].freeze

    module_function

    def csv
      overrides = PriceOverride.for_active_round.order(:erp_product_id).to_a
      products = Product.where(erp_product_id: overrides.map(&:erp_product_id)).includes(:price)
                        .index_by(&:erp_product_id)

      SafeCsv.generate do |csv|
        csv << HEADERS
        overrides.each do |o|
          product = products[o.erp_product_id]
          erp = product&.price&.credit_wholesale_price
          csv << [ Product.erp_code_for(o.erp_product_id), SafeCsv.text(product&.description), erp&.to_s("F"),
                   o.unit_price.to_s("F"), PriceList.variation_label((o.unit_price / erp - 1 if erp&.positive?)),
                   SafeCsv.text(o.source_filename), SafeCsv.text(o.loaded_by), o.updated_at.in_time_zone.strftime("%d/%m/%Y %H:%M") ]
        end
      end
    end
  end
end
