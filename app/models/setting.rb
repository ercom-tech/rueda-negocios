class Setting < ApplicationRecord
  # Configuración local de la laptop-servidor. Fila única (singleton).
  belongs_to :selected_round, class_name: "BusinessRound",
             foreign_key: :selected_round_erp_id, primary_key: :erp_round_id,
             optional: true

  # La única fila de settings; se crea al primer acceso. El índice único
  # `index_settings_singleton` garantiza la unicidad en BD: si dos procesos
  # crean a la vez, el perdedor relee la fila ganadora.
  def self.instance
    first || create!
  rescue ActiveRecord::RecordNotUnique
    first
  end

  # Siguiente número del folio de cotización (ver Order#generate_local_folio).
  # Con candado de fila: dos capturistas guardando a la vez no deben sacar el
  # mismo número. No retrocede cuando se borran cotizaciones.
  def self.next_estimate_number!
    setting = instance
    setting.with_lock do
      setting.increment!(:last_estimate_number)
      setting.last_estimate_number
    end
  end
end
