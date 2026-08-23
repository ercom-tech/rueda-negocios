class PromotionGift < ApplicationRecord
  # Producto que se regala al alcanzar un escalón (vta_promocion_regalo).
  # Cuelga del escalón, no de la promoción.

  belongs_to :promotion_tier
  belongs_to :product
end
