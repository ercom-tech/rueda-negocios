class Order < ApplicationRecord
  # Pedido levantado por el capturista. No lleva proveedor: puede mezclar
  # productos de distintos proveedores.

  belongs_to :user
  belongs_to :business_round
  belongs_to :client
  belongs_to :client_tax_profile,     optional: true
  belongs_to :client_receipt_profile, optional: true
  belongs_to :client_branch,          optional: true
  belongs_to :cfdi_use,               optional: true

  has_many :order_items, -> { order(:position) }, dependent: :destroy

  enum :kind,   { invoice: "invoice", remission: "remission" }
  enum :status, { draft: "draft", submitted: "submitted" }

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

  private

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
