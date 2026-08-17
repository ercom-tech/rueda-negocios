class Price < ApplicationRecord
  # Precio activo del producto. Crédito mayoreo es el que COBRA la rueda
  # (decisión FECEGO 2026-08-17); público y mayoreo son referencia. Uno por
  # producto.

  belongs_to :product

  validates :product_id, uniqueness: true
end
