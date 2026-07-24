class Product < ApplicationRecord
  # Producto (com_producto). erp_product_id es el Código FECEGO (SKU oficial).

  belongs_to :brand, optional: true

  has_one :price, dependent: :destroy

  has_many :product_suppliers, dependent: :destroy
  has_many :suppliers, through: :product_suppliers

  validates :erp_product_id, presence: true, uniqueness: true
end
