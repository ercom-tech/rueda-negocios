class Price < ApplicationRecord
  # Precio activo del producto (público y mayoreo). Uno por producto.

  belongs_to :product

  validates :product_id, uniqueness: true
end
