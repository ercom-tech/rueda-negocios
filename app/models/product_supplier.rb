class ProductSupplier < ApplicationRecord
  # Unión producto ↔ proveedor (com_proveedor_has_producto), con el SKU
  # del proveedor (distinto por proveedor).

  belongs_to :product
  belongs_to :supplier

  validates :product_id, uniqueness: { scope: :supplier_id }
end
