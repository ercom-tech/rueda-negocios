class Brand < ApplicationRecord
  # Marca (com_marca).

  has_many :products, dependent: :nullify

  has_and_belongs_to_many :suppliers, join_table: :brands_suppliers
  has_and_belongs_to_many :business_rounds, join_table: :business_round_brands

  validates :erp_brand_id, presence: true, uniqueness: true
end
