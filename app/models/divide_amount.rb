class DivideAmount < ApplicationRecord
  # Monto de división de facturas (catálogo vta_pedido_monto_divide del ERP):
  # opciones del combo "Dividir facturas cada ($)" del paso 1. El pedido NO
  # guarda FK a este catálogo — guarda el monto mismo, igual que vta_pedido.

  validates :erp_consecutive, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:amount) }

  def label
    amount.zero? ? "No dividir" : ActiveSupport::NumberHelper.number_to_currency(amount, precision: 0)
  end

  # Valor plano para el combo/selected (sin ceros insignificantes): "0", "2000".
  def option_value
    ActiveSupport::NumberHelper.number_to_rounded(amount, strip_insignificant_zeros: true, delimiter: "")
  end
end
