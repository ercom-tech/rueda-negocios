class BusinessRoundPerson < ApplicationRecord
  # Persona (usuario/capturista) ligada a un proveedor en una rueda
  # (cnf_rueda_negocios_persona). Marca opcional.

  belongs_to :business_round
  belongs_to :user
  belongs_to :supplier
  belongs_to :brand, optional: true

  validates :user_id, uniqueness: { scope: %i[business_round_id consecutivo] }
end
