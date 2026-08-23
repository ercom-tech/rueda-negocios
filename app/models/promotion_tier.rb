class PromotionTier < ApplicationRecord
  # Un escalón de una promoción (vta_promocion_detalle).

  belongs_to :promotion
  has_many :promotion_gifts, dependent: :destroy
  has_many :gift_products, through: :promotion_gifts, source: :product

  # Semántica del ERP (confirmada por FECEGO 2026-08-22):
  #   CE = "en la compra de entre X y Y"
  #   CM = "en la compra mínima de X"   (quantity_to viene en 0)
  #   PC = "por cada X"
  #
  # PC no aparece en las 38 promociones de la rueda, y su regla ("por cada")
  # no es la de un escalón: multiplica. Se reconoce para NO aplicarlo con la
  # semántica equivocada — un escalón PC que llegara del ERP no cubre nada y
  # la promoción se comporta como si no alcanzara, en vez de regalar
  # descuentos que nadie prometió.
  BETWEEN = "CE".freeze
  MINIMUM = "CM".freeze
  PER_EACH = "PC".freeze

  def covers?(amount)
    return false if amount.blank? || amount < quantity_from

    case condition_kind
    when MINIMUM then true
    when BETWEEN then quantity_to.zero? || amount <= quantity_to
    else false # PC y cualquier tipo nuevo: no se aplica a ciegas
    end
  end

  def supported?
    [ BETWEEN, MINIMUM ].include?(condition_kind)
  end

  def gifts?
    promotion_gifts.any?
  end

  # Rótulo del escalón para el modal, en el lenguaje del ERP.
  # La cifra se formatea según la unidad: MXN mide importe, PZA piezas.
  def condition_label
    case condition_kind
    when MINIMUM then "En la compra mínima de #{format_amount(quantity_from)}"
    when BETWEEN then "En la compra de entre #{format_amount(quantity_from)} y #{format_amount(quantity_to)}"
    when PER_EACH then "Por cada #{format_amount(quantity_from)}"
    else "Condición no reconocida (#{condition_kind})"
    end
  end

  def format_amount(value)
    if promotion.measured_in_money?
      ActiveSupport::NumberHelper.number_to_currency(value, precision: 0)
    else
      pieces = ActiveSupport::NumberHelper.number_to_rounded(value, strip_insignificant_zeros: true)
      "#{pieces} #{value == 1 ? 'pieza' : 'piezas'}"
    end
  end
end
