class PromotionProduct < ApplicationRecord
  # Renglón del universo de una promoción (vta_promocion_codigo): este
  # producto participa, y opcionalmente con su propio descuento.

  belongs_to :promotion
  belongs_to :product
end
