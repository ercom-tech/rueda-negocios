class BusinessRound < ApplicationRecord
  # Rueda de negocios (cnf_rueda_negocios). Evento con sus participantes.

  has_and_belongs_to_many :suppliers,    join_table: :business_round_suppliers
  has_and_belongs_to_many :brands,       join_table: :business_round_brands
  has_and_belongs_to_many :salespeople,  join_table: :business_round_salespeople

  has_many :business_round_clients, dependent: :destroy
  has_many :clients, through: :business_round_clients

  has_many :business_round_people, dependent: :destroy

  validates :erp_round_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }
end
