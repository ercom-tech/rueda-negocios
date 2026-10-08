class PriceOverride < ApplicationRecord
  # Precio unitario cargado desde un archivo en el panel del servidor
  # (2026-10-08). Reemplaza al crédito mayoreo del ERP al capturar, sin tocar
  # el ERP. Ver la migración para por qué va por código y rueda, sin FK.
  #
  # Los archivos se SUMAN: cargar uno nuevo solo cambia sus códigos, y en un
  # código repetido gana el último que se cargó.

  # Mismo tope que la partida: un precio que la partida no aceptaría no se
  # puede cargar aquí.
  validates :erp_round_id, :erp_product_id, presence: true
  validates :erp_product_id, uniqueness: { scope: :erp_round_id }
  validates :unit_price, numericality: { greater_than: 0, less_than: OrderItem::MAX_UNIT_PRICE }
  # El 999999 no tiene precio de lista: se captura a mano en cada partida.
  validates :erp_product_id, exclusion: { in: [ Product::GENERIC_ERP_ID ] }

  # Los de la rueda activa. Sin rueda activa no aplica ninguno.
  scope :for_active_round, -> { where(erp_round_id: BusinessRound.active.select(:erp_round_id)) }
end
