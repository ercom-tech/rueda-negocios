class Supplier < ApplicationRecord
  # Proveedor (com_proveedor).

  has_and_belongs_to_many :brands, join_table: :brands_suppliers

  has_many :product_suppliers, dependent: :destroy
  has_many :products, through: :product_suppliers

  has_and_belongs_to_many :business_rounds, join_table: :business_round_suppliers

  validates :erp_supplier_id, presence: true, uniqueness: true
end
