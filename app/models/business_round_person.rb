class BusinessRoundPerson < ApplicationRecord
  # Persona (usuario/capturista) ligada a un proveedor y/o una marca en una
  # rueda (cnf_rueda_negocios_persona). El ERP modela "solo marca" con
  # id_proveedor = 0 y "solo proveedor" con id_marca = 0: aquí ambos son
  # opcionales, pero al menos uno debe venir.

  belongs_to :business_round
  belongs_to :user
  belongs_to :supplier, optional: true
  belongs_to :brand, optional: true

  validates :user_id, uniqueness: { scope: %i[business_round_id position] }
  validate :supplier_or_brand_present

  private

  def supplier_or_brand_present
    return if supplier_id.present? || brand_id.present?

    errors.add(:base, "La membresía necesita proveedor o marca.")
  end
end
