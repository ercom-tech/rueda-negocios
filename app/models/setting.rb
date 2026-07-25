class Setting < ApplicationRecord
  # Configuración local de la laptop-servidor. Fila única (singleton).
  belongs_to :selected_round, class_name: "BusinessRound",
             foreign_key: :selected_round_erp_id, primary_key: :erp_round_id,
             optional: true

  # La única fila de settings; se crea al primer acceso.
  def self.instance
    first || create!
  end
end
