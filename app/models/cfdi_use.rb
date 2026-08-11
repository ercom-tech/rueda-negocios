class CfdiUse < ApplicationRecord
  # Catálogo SAT de uso de CFDI.

  validates :code, presence: true, uniqueness: true

  def label
    [ code, description ].compact_blank.join(" — ")
  end
end
