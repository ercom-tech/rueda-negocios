class Client < ApplicationRecord
  # Cliente (vta_cliente).

  belongs_to :salesperson, optional: true

  has_many :business_round_clients, dependent: :destroy
  has_many :business_rounds, through: :business_round_clients

  has_many :tax_profiles,     class_name: "ClientTaxProfile",     dependent: :destroy
  has_many :receipt_profiles, class_name: "ClientReceiptProfile", dependent: :destroy
  has_many :branches,         class_name: "ClientBranch",         dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :erp_client_key, presence: true, uniqueness: true
end
