class Client < ApplicationRecord
  # Cliente (vta_cliente).

  belongs_to :salesperson, optional: true

  has_many :business_round_clients, dependent: :destroy
  has_many :business_rounds, through: :business_round_clients

  validates :erp_client_key, presence: true, uniqueness: true
end
