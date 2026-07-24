class BusinessRoundClient < ApplicationRecord
  # Cliente registrado en una rueda (cnf_rueda_negocios_cliente), con banderas
  # de aprobación de ventas/crédito y el crédito autorizado.

  belongs_to :business_round
  belongs_to :client
  belongs_to :salesperson, optional: true

  validates :business_round_id, uniqueness: { scope: :client_id }
end
