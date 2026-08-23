class OrderItem < ApplicationRecord
  # Partida del pedido (snapshot de los datos del producto).

  # `touch: true`: el sync-up detecta "editado mientras se transmitía"
  # comparando `order.updated_at`. Aplicar una promoción cambia el descuento de
  # todo el grupo y agrega un renglón sin tocar el pedido, así que ese aviso
  # —construido en la 5ª auditoría— nunca se disparaba (7ª auditoría).
  belongs_to :order, touch: true
  belongs_to :product, optional: true
  belongs_to :promotion,      optional: true
  belongs_to :promotion_tier, optional: true

  # Bandera de "este cambio lo está haciendo el sistema, no el capturista":
  # la pone `Promotions::Group` al aplicar y al quitar una promoción. Sin
  # ella, el candado de abajo bloquearía a la propia rutina que aplica el
  # descuento. No es un atributo de la tabla y no se puede llegar a ella
  # desde `params`, así que un PATCH forjado nunca la activa.
  attr_accessor :promotion_managed

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
  validate :promotion_not_applied_to_product, on: :create
  validate :not_locked_by_promotion, on: :update
  # El candado de edición es `on: :update` y NO cubría el borrado: la pantalla
  # esconde el bote de basura en una fila congelada, pero el endpoint seguía
  # vivo — una pestaña rezagada o un DELETE forjado alcanzaban la partida. Y
  # borrar PARTE de un grupo no recalcula el escalón: el resto conservaba un
  # descuento que ya no se gana y se transmitía al ERP (7ª auditoría).
  before_destroy :block_destroy_when_locked

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
    # El regalo queda fuera: su cantidad la dicta el ERP en
    # `vta_promocion_regalo`, no el capturista, y si no cuadra con el empaque
    # no hay nada que corregir desde aquí — solo dejaría la promoción
    # inaplicable en pleno evento (7ª auditoría).
    return if gift?

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
    # El tope del producto NO limita a una promoción: es la brida del
    # descuento que teclea el capturista. En el ERP, de las 66,304 partidas
    # históricas donde la promoción rebasaba el tope del producto, en 66,300
    # ganó la promoción completa. Y en la rueda el choque sería masivo: los
    # topes de los 6,046 productos en promoción son de 3% a 9% contra
    # descuentos de hasta 23%, así que con el tope encima casi ninguna
    # promoción se podría aplicar.
    elsif promotion_id.present?
      errors.add(:base, "El descuento no puede exceder 100%.") if discount_percent > 100
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
    # Los regalos no cuentan contra el tope (decisión FECEGO 2026-08-22): el
    # capturista no los pidió y no debe perder un renglón propio por ellos.
    # El ERP aguanta de sobra — su histórico llega a 287 partidas.
    return if gift? || order.blank? || !order.items_limit_reached?

    errors.add(:base, "Un pedido no puede tener más de #{Order::MAX_ITEMS} partidas.")
  end

  # --- Promociones -------------------------------------------------------

  # La promoción de la rueda a la que pertenece este producto en una fecha,
  # esté aplicada o no. Es lo que enciende la flama de la fila.
  def promotion_on(date)
    return nil if gift?

    Promotion.for_product(product, on: date)
  end

  # Congelada por una promoción aplicada: ni se edita ni se quita hasta que
  # la promoción se retire (decisión FECEGO 2026-08-22). Los regalos lo están
  # siempre — los pone y los quita el sistema.
  def locked_by_promotion?
    gift? || promotion_id.present?
  end

  # Campos que el candado protege. Es la lista de lo que el capturista puede
  # tocar de una partida; `position` no está porque la renumeración es del
  # sistema y corre justo al quitar los regalos.
  LOCKED_FIELDS = %w[quantity unit_price discount_percent description part_number].freeze

  def not_locked_by_promotion
    return if promotion_managed
    # El valor ANTERIOR, no el nuevo: al quitar la promoción `promotion_id`
    # ya viene en nil y el candado se abriría justo cuando debe cerrarse.
    return unless gift? || promotion_id_was.present?
    return if (changed & LOCKED_FIELDS).empty?

    errors.add(:base, gift? ?
      "Esta partida es un regalo de la promoción y la pone el sistema. " \
      "Quita la promoción si necesitas cambiarla." :
      "Esta partida tiene la promoción \"#{promotion&.name || promotion_was_name}\" aplicada. " \
      "Quita la promoción para editarla, y vuelve a aplicarla al terminar.")
  end

  # Un producto de una promoción YA aplicada no se puede agregar: cambiaría
  # el acumulado del grupo, pero sus partidas están congeladas y el descuento
  # se quedaría calculado sobre una suma vieja (decisión del usuario
  # 2026-08-22, opción 1 de las tres que se plantearon). El camino es el
  # mismo que para editar: quitar, agregar y volver a aplicar.
  def promotion_not_applied_to_product
    return if gift? || order.blank? || product.blank?

    applied = order.applied_promotion_for(product)
    return if applied.nil?

    errors.add(:base, "Este producto es de la promoción \"#{applied.name}\", que ya está aplicada. " \
                      "Quita la promoción para agregarlo, y vuelve a aplicarla al terminar.")
  end

  def promotion_was_name
    Promotion.find_by(id: promotion_id_was)&.name
  end

  # `throw :abort` y no una validación: `destroy` no corre validaciones.
  def block_destroy_when_locked
    return if promotion_managed || !locked_by_promotion?

    errors.add(:base, gift? ?
      "Esta partida es un regalo de la promoción y la pone el sistema. " \
      "Quita la promoción si necesitas cambiarla." :
      "Esta partida tiene la promoción \"#{promotion&.name}\" aplicada. " \
      "Quita la promoción para quitarla del pedido.")
    throw :abort
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
