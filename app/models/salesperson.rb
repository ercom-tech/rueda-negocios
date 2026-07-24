class Salesperson < ApplicationRecord
  # Vendedor (vta_vendedor). La persona física vive en el ERP (cnf_persona)
  # vía erp_person_id (puede ser 0/nil).

  has_many :clients, dependent: :nullify
  has_and_belongs_to_many :business_rounds, join_table: :business_round_salespeople

  validates :erp_salesperson_id, presence: true, uniqueness: true
end
