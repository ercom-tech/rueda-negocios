class Order < ApplicationRecord
  # Tope de partidas por pedido: regla de negocio de la rueda (el ERP NO la
  # impone — su histórico llega a 287 renglones). Puede subir cuando entren
  # los regalos por promoción.
  MAX_ITEMS = 45

  # Las observaciones viajan al ERP, que maneja texto en mayúsculas: se
  # normalizan aquí (fuente de verdad); el `uppercase` del textarea es solo
  # presentación mientras se teclea.
  normalizes :observations, with: ->(text) { text.upcase }

  # Importe máximo por factura al facturar el pedido (vta_pedido.
  # dividir_facturas); 0 = no dividir. Solo tiene sentido en facturas, pero
  # se guarda siempre (0) para transmitir el encabezado completo.
  validates :dividir_facturas, numericality: { greater_than_or_equal_to: 0 }

  # Valor plano para el combo del paso 1 ("0", "2000") — mismo formato que
  # DivideAmount#option_value para que `selected` empareje.
  def dividir_facturas_option
    ActiveSupport::NumberHelper.number_to_rounded(dividir_facturas || 0,
                                                  strip_insignificant_zeros: true, delimiter: "")
  end

  # Pedido levantado por el capturista. No lleva proveedor: puede mezclar
  # productos de distintos proveedores.

  belongs_to :user
  belongs_to :business_round
  belongs_to :client
  belongs_to :client_tax_profile,     optional: true
  belongs_to :client_receipt_profile, optional: true
  belongs_to :client_branch,          optional: true
  belongs_to :cfdi_use,               optional: true

  # `includes(:product)`: cada renglón de la tabla de partidas necesita el
  # empaque mínimo de su producto, y sin precargarlo eran 45 consultas extra en
  # CADA repintado — o sea en cada alta, baja y edición de cantidad, que es el
  # flujo más usado del evento y desde una tablet.
  has_many :order_items, -> { order(:position).includes(:product) }, dependent: :destroy

  enum :kind,   { invoice: "invoice", remission: "remission" }
  # draft: en captura · captured: finalizado por el capturista, editable ·
  # transmitted: ya en el ERP (folio asignado), NO editable.
  enum :status, { draft: "draft", captured: "captured", transmitted: "transmitted" }

  validates :kind, presence: true
  validate  :header_selections_present

  def subtotal
    order_items.sum(&:line_total)
  end

  def discount_total
    order_items.sum(&:discount_amount)
  end

  def tax_total
    order_items.sum(&:tax_amount)
  end

  def total
    subtotal - discount_total + tax_total
  end

  def next_item_position
    (order_items.maximum(:position) || 0) + 1
  end

  # Reacomoda el consecutivo a 1..N tras borrar una partida: sin esto, quitar
  # una intermedia dejaba huecos en la columna Consecutivo. `update_column`
  # a propósito — no es un cambio de negocio sino de orden, y una partida con
  # algún problema previo no debe bloquear la renumeración del resto.
  def renumber_items!
    transaction do
      order_items.reload.each_with_index do |item, i|
        item.update_column(:position, i + 1) unless item.position == i + 1
      end
    end
  end

  # Partidas que cuentan contra MAX_ITEMS. Punto ÚNICO de la regla (lo usan la
  # validación de OrderItem y el contador de la vista): cuando lleguen los
  # regalos por promoción, aquí se decide si se excluyen del conteo.
  def items_count_for_limit
    order_items.count
  end

  def items_limit_reached?
    items_count_for_limit >= MAX_ITEMS
  end

  # Finaliza la captura: asigna folio local y marca el pedido como capturado.
  def capture!
    return false if order_items.empty?

    update!(status: :captured, local_folio: local_folio.presence || generate_local_folio)
  end

  # Editable mientras no se haya transmitido al ERP.
  def editable?
    !transmitted?
  end

  STATUS_LABELS = { "draft" => "Borrador", "captured" => "Capturado", "transmitted" => "Transmitido" }.freeze

  # Importe de las partidas con descuento e IVA — la misma fórmula de
  # OrderItem#total, pero EN SQL: `Order#total` se calcula en Ruby, así que
  # totalizar un reporte con él obligaría a cargar cada pedido con todas sus
  # partidas (300 pedidos × 45 renglones) cada vez que se abre la pantalla.
  ITEM_TOTAL_SQL = <<~SQL.squish.freeze
    order_items.quantity * order_items.unit_price
      * (1 - order_items.discount_percent / 100.0)
      * (1 + order_items.tax_rate / 100.0)
  SQL

  ITEMS_TOTAL_SQL = "COALESCE(SUM(#{ITEM_TOTAL_SQL}), 0)".freeze

  # Igual, pero sumando SOLO las partidas de los productos recibidos (?).
  MATCHING_ITEMS_TOTAL_SQL =
    "COALESCE(SUM(CASE WHEN order_items.product_id IN (?) THEN #{ITEM_TOTAL_SQL} ELSE 0 END), 0)".freeze

  # Resumen { estatus => { count:, total: } } del alcance recibido — se llama
  # sobre el scope ya acotado por rol y por los filtros, de modo que resumen y
  # listado no puedan divergir. Devuelve SIEMPRE los tres estatus, con ceros
  # los que no tengan pedidos: las tarjetas del reporte son también el filtro
  # de estatus y deben mostrarse completas.
  #
  # `products` (subconsulta de ids) restringe la suma a las partidas de esos
  # productos: con un filtro de proveedor/marca/producto activo, el importe que
  # se reporta es el de las partidas que coinciden, no el del pedido completo.
  # Va como CASE dentro del SUM y no como condición del join, para que el
  # conteo de pedidos no cambie y los pedidos sin partidas sigan apareciendo.
  def self.totals_by_status(products = nil)
    suma = products ? sanitize_sql_array([ MATCHING_ITEMS_TOTAL_SQL, products ]) : ITEMS_TOTAL_SQL

    filas = reorder(nil).left_joins(:order_items).group(:status)
                        .pluck(Arel.sql("orders.status"),
                               Arel.sql("COUNT(DISTINCT orders.id)"),
                               Arel.sql(suma))
                        .to_h { |status, count, total| [status, { count: count, total: total }] }

    statuses.keys.index_with { |status| filas[status] || { count: 0, total: 0 } }
  end

  # Clases Tailwind del badge de estatus (mismas en reporte y detalle).
  STATUS_COLORS = {
    "draft"       => "bg-neutral-200 text-neutral-700",
    "captured"    => "bg-brand-gold text-neutral-900",
    "transmitted" => "bg-brand-coral text-white"
  }.freeze

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  def status_color
    STATUS_COLORS.fetch(status, STATUS_COLORS["draft"])
  end

  # Identificador visible del pedido, con UNA sola precedencia para todas las
  # pantallas: el folio local (`RN-000123`) existe desde que se captura y es el
  # que va en el PDF; el del ERP solo aparece si por alguna razón faltara el
  # local. Antes cada pantalla resolvía distinto —el paso 2 prefería el del ERP,
  # el paso 3 y el PDF el local, el reporte solo el local— y el mismo pedido se
  # llamaba de dos formas según dónde se mirara.
  def folio
    local_folio.presence || erp_folio.presence || "(borrador)"
  end

  private

  def generate_local_folio
    "RN-#{id.to_s.rjust(6, "0")}"
  end


  # Fuerza los datos obligatorios del encabezado (paso 1).
  def header_selections_present
    if invoice?
      errors.add(:client_tax_profile_id, "es obligatorio para factura") if client_tax_profile_id.blank?
      errors.add(:cfdi_use_id, "es obligatorio para factura")           if cfdi_use_id.blank?
    elsif remission? && client&.receipt_profiles&.exists? && client_receipt_profile_id.blank?
      errors.add(:client_receipt_profile_id, "es obligatoria para remisión")
    end

    if client&.branches&.exists? && client_branch_id.blank?
      errors.add(:client_branch_id, "es obligatoria")
    end
  end
end
