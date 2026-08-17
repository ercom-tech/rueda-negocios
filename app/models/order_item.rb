class OrderItem < ApplicationRecord
  # Partida del pedido (snapshot de los datos del producto).

  belongs_to :order
  belongs_to :product, optional: true

  # Borrar el campo de descuento significa "sin descuento": normalizar a 0
  # antes de validar — la columna es NOT NULL (borrar + tab tronaba con
  # PG::NotNullViolation) y los cálculos dividen sobre el valor.
  before_validation { self.discount_percent = 0 if discount_percent.blank? }
  before_validation :normalize_generic_fields, if: :generic?

  validates :tax_rate, numericality: { greater_than_or_equal_to: 0 }
  validate :quantity_positive
  validate :quantity_in_package_multiples
  validate :unit_price_positive
  validate :discount_within_limits
  validate :generic_description_fits_erp, if: :generic?
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

  # Tope de la columna (`numeric(14,4)`): un precio tecleado de más en el
  # genérico saldría como ActiveRecord::RangeError, que ningún rescue atrapa,
  # y en una respuesta Turbo Stream el capturista solo vería que "no pasó
  # nada" (misma trampa que la cantidad).
  MAX_UNIT_PRICE = 10**10

  # Un producto sin precio (sync sin renglón de precio → snapshot 0) no debe
  # venderse: transmitiría una partida en $0 al ERP sin que nadie lo note.
  # En el genérico el precio es capturado: el mensaje pide escribirlo.
  def unit_price_positive
    unless unit_price.present? && unit_price.positive?
      # Ambos mensajes dicen la salida: al genérico, que el precio debe ser
      # mayor a cero (un 0 tecleado leía "escríbelo" — ya lo había escrito);
      # al catálogo, los dos caminos que sí existen (6ª auditoría).
      return errors.add(:base, generic? ? "Escribe el precio unitario (mayor a cero)." :
                                          "El producto no tiene precio de rueda; no se puede agregar del catálogo. " \
                                          "Captúralo fuera de catálogo (999999) con su precio, o avisa al equipo del servidor.")
    end

    errors.add(:base, "El precio es demasiado grande.") if unit_price >= MAX_UNIT_PRICE
  end

  # El descuento no puede exceder el máximo del producto (`max_discount`, %
  # sincronizado del ERP). Sin dato (nil, o partida sin producto) se trata
  # como 0: no aplica descuentos (decisión del usuario, 2ª auditoría B1).
  # En el genérico el descuento es libre (decisión FECEGO 2026-08-17): solo
  # lo acotan el 0 y el 100.
  def discount_within_limits
    return if discount_percent.blank?

    if discount_percent.negative?
      errors.add(:base, "El descuento no puede ser negativo.")
    elsif !generic? && discount_percent > (cap = product&.max_discount || 0)
      # El tope del producto va primero: con 150 tecleado, "no puede exceder
      # 100%" escondía el tope real hasta el segundo intento (6ª auditoría).
      errors.add(:base, "El descuento no puede exceder el máximo del producto (#{cap.to_i}%).")
    elsif discount_percent > 100
      errors.add(:base, "El descuento no puede exceder 100%.")
    end
  end

  # --- Producto fuera de catálogo (genérico 999999) ----------------------
  # Su partida captura descripción, no. de parte y precio a mano; en el
  # resto de los productos esos campos son snapshot del ERP.

  ERP_CAPTURED_NAME_LIMIT = 40

  def generic?
    product&.generic? || false
  end

  # Lo que viaja al ERP en `vta_pedido_detalle.nombre_capturado`
  # (varchar 40): descripción y no. de parte juntos, como lo captura el
  # propio ERP en sus pedidos nativos con el genérico.
  def erp_captured_name
    [ description, part_number.presence ].compact.join(" ")
  end

  # Mayúsculas como el resto del catálogo (y como los nativos del ERP). Los
  # caracteres de control (saltos, tabs, escapes — solo alcanzables por
  # payload forjado) se colapsan a espacio: viajaban crudos al ERP y al PDF.
  # El precio se fija a 2 decimales: el papel imprime a 2 y con 4 el renglón
  # no cuadraba con su Monto para un cliente con calculadora (6ª auditoría).
  def normalize_generic_fields
    self.description = description.to_s.gsub(/[[:cntrl:]]/, " ").squish.upcase
    self.part_number = part_number.to_s.gsub(/[[:cntrl:]]/, " ").squish.upcase.presence
    self.unit_price  = unit_price.round(2) if unit_price
  end

  def generic_description_fits_erp
    return errors.add(:base, "Escribe la descripción del producto.") if description.blank?

    over = erp_captured_name.length - ERP_CAPTURED_NAME_LIMIT
    return unless over.positive?

    errors.add(:base, "La descripción y el número de parte viajan juntos al ERP y no caben: " \
                      "#{over == 1 ? 'sobra 1 carácter' : "sobran #{over} caracteres"} " \
                      "(máximo #{ERP_CAPTURED_NAME_LIMIT} entre ambos).")
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
