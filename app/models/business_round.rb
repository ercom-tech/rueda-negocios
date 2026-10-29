class BusinessRound < ApplicationRecord
  # Rueda de negocios (cnf_rueda_negocios). Evento con sus participantes.

  has_and_belongs_to_many :suppliers,    join_table: :business_round_suppliers
  has_and_belongs_to_many :brands,       join_table: :business_round_brands
  has_and_belongs_to_many :salespeople,  join_table: :business_round_salespeople

  has_many :business_round_clients, dependent: :destroy
  has_many :clients, through: :business_round_clients

  has_many :business_round_people, dependent: :destroy

  validates :erp_round_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }

  # Un prefijo que la API leería como cotización: rechaza toda clave con el
  # segmento `COT-` (15ª auditoría), así que una rueda con prefijo `COT` daría
  # folios de venta `COT-000123` idénticos a los de una cotización, y NINGUNA
  # venta se transmitiría — sin salida, porque el folio ya quedó fijo (16ª).
  # Ninguna regla de la API puede distinguirlos: el texto es el mismo. Mismo
  # recorte que la regla de la API (`/(\A|-)COT-/i` sobre la clave): "XCOT" y
  # "COTA" no chocan; "-COT" y "COT-" sí. El de "COT-" se escapaba —la clave
  # sale `COT--000123`— y la API rechazaba todas las ventas (17ª auditoría).
  RESERVED_FOLIO_PREFIX = /(\A|-)COT(-|\z)/i

  def reserved_folio_prefix?
    folio_prefix.to_s.match?(RESERVED_FOLIO_PREFIX)
  end

  # El prefijo con el que salen los PEDIDOS: nil si no hay o si está reservado,
  # y entonces el pedido toma el respaldo (`Order::DEFAULT_FOLIO_PREFIX`).
  def sale_folio_prefix
    folio_prefix.presence unless reserved_folio_prefix?
  end
end
