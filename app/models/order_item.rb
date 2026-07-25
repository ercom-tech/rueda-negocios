class OrderItem < ApplicationRecord
  # Partida del pedido (snapshot de los datos del producto).

  belongs_to :order
  belongs_to :product, optional: true

  validates :quantity, numericality: { greater_than: 0 }
  validates :discount_percent, :tax_rate, numericality: { greater_than_or_equal_to: 0 }

  # Total de la partida = cantidad × precio (el descuento y el IVA se aplican
  # al agregado, como en la referencia).
  def line_total
    quantity * unit_price
  end

  def discount_amount
    line_total * (discount_percent / 100)
  end

  def taxable
    line_total - discount_amount
  end

  def tax_amount
    taxable * (tax_rate / 100)
  end

  # Total de la partida con IVA (para el PDF, estilo b2b).
  def total
    taxable + tax_amount
  end
end
