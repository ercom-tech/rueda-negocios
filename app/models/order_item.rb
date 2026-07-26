class OrderItem < ApplicationRecord
  # Partida del pedido (snapshot de los datos del producto).

  belongs_to :order
  belongs_to :product, optional: true

  validates :tax_rate, numericality: { greater_than_or_equal_to: 0 }
  validate :quantity_positive
  validate :discount_within_limits

  # Mensajes en `:base` (sin default_locale :es, que alteraría formatos de
  # moneda/fecha en toda la UI): así `full_messages` los muestra tal cual, en
  # español, para el flash de OrderItems#update.
  def quantity_positive
    errors.add(:base, "La cantidad debe ser mayor a 0.") if quantity.blank? || quantity <= 0
  end

  # El descuento no puede exceder el máximo del producto (`max_discount`, %
  # sincronizado del ERP). Si el producto no trae tope (nil) se permite hasta
  # 100 %; el ERP usa 0 para "sin descuento", así que 0 sí bloquea descuentos.
  def discount_within_limits
    return if discount_percent.blank?

    if discount_percent.negative?
      errors.add(:base, "El descuento no puede ser negativo.")
    elsif discount_percent > (cap = product&.max_discount || 100)
      errors.add(:base, "El descuento no puede exceder el máximo del producto (#{cap.to_i}%).")
    end
  end

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
