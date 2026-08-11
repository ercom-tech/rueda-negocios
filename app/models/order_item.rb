class OrderItem < ApplicationRecord
  # Partida del pedido (snapshot de los datos del producto).

  belongs_to :order
  belongs_to :product, optional: true

  # Borrar el campo de descuento significa "sin descuento": normalizar a 0
  # antes de validar — la columna es NOT NULL (borrar + tab tronaba con
  # PG::NotNullViolation) y los cálculos dividen sobre el valor.
  before_validation { self.discount_percent = 0 if discount_percent.blank? }

  validates :tax_rate, numericality: { greater_than_or_equal_to: 0 }
  validate :quantity_positive
  validate :quantity_in_package_multiples
  validate :unit_price_positive
  validate :discount_within_limits
  # Solo al agregar: un pedido que YA rebasa el tope (p.ej. si la regla baja
  # después) debe seguir siendo editable — corregir cantidades y quitar
  # renglones — en vez de quedar atorado sin poder guardar nada.
  validate :order_items_within_limit, on: :create

  # Mensajes en `:base` (sin default_locale :es, que alteraría formatos de
  # moneda/fecha en toda la UI): así `full_messages` los muestra tal cual, en
  # español, para el flash de OrderItems#update.
  # El tope superior es el de la columna (`numeric(14,3)`): sin él, una cantidad
  # pegada o tecleada de más salía del `update` como ActiveRecord::RangeError,
  # que ningún rescue atrapa. Como el PATCH es un Turbo Stream, la tabla no se
  # repintaba y el capturista solo veía que "no pasó nada", sin mensaje.
  MAX_QUANTITY = 10**11

  def quantity_positive
    return errors.add(:base, "La cantidad debe ser mayor a 0.") if quantity.blank? || quantity <= 0

    errors.add(:base, "La cantidad es demasiado grande.") if quantity >= MAX_QUANTITY
  end

  # Empaque mínimo de venta (com_producto_has_empaque): el producto solo se
  # vende en múltiplos de min_sale_quantity. Sin dato (nil) no hay regla.
  def quantity_in_package_multiples
    min = product&.min_sale_quantity
    return if min.blank? || min <= 0 || quantity.blank? || quantity <= 0
    return if (quantity % min).zero?

    errors.add(:base, "El producto se vende en múltiplos de " \
                      "#{ActiveSupport::NumberHelper.number_to_rounded(min, strip_insignificant_zeros: true)} " \
                      "(empaque mínimo de venta).")
  end

  # Un producto sin precio (sync sin renglón de precio → snapshot 0) no debe
  # venderse: transmitiría una partida en $0 al ERP sin que nadie lo note.
  def unit_price_positive
    return if unit_price.present? && unit_price.positive?

    errors.add(:base, "El producto no tiene precio de rueda; no se puede agregar al pedido.")
  end

  # El descuento no puede exceder el máximo del producto (`max_discount`, %
  # sincronizado del ERP). Sin dato (nil, o partida sin producto) se trata
  # como 0: no aplica descuentos (decisión del usuario, 2ª auditoría B1).
  def discount_within_limits
    return if discount_percent.blank?

    if discount_percent.negative?
      errors.add(:base, "El descuento no puede ser negativo.")
    elsif discount_percent > (cap = product&.max_discount || 0)
      errors.add(:base, "El descuento no puede exceder el máximo del producto (#{cap.to_i}%).")
    end
  end

  # Tope de partidas del pedido (Order::MAX_ITEMS). Va en el modelo y no solo
  # en el controlador: cubre cualquier ruta futura y un POST forjado por igual.
  # El controlador ya muestra estos mensajes en el flash cuando `save` falla.
  def order_items_within_limit
    return if order.blank? || !order.items_limit_reached?

    errors.add(:base, "Un pedido no puede tener más de #{Order::MAX_ITEMS} partidas.")
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
