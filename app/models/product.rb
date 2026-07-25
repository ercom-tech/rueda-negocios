class Product < ApplicationRecord
  # Producto (com_producto). erp_product_id es el Código FECEGO (SKU oficial).

  belongs_to :brand, optional: true

  has_one :price, dependent: :destroy

  has_many :product_suppliers, dependent: :destroy
  has_many :suppliers, through: :product_suppliers

  validates :erp_product_id, presence: true, uniqueness: true

  # Búsqueda por código FECEGO, código de proveedor (SKU), nombre, modelo o
  # número de parte.
  scope :search, ->(query) {
    like = "%#{query.to_s.strip}%"
    left_joins(:product_suppliers)
      .where(
        "CAST(products.erp_product_id AS TEXT) ILIKE :q OR products.description ILIKE :q " \
        "OR products.model ILIKE :q OR products.part_number ILIKE :q " \
        "OR product_suppliers.supplier_sku ILIKE :q",
        q: like
      )
      .distinct
  }

  # Snapshot para crear una partida de pedido.
  def to_order_item_attributes
    {
      product:     self,
      code:        erp_product_id.to_s,
      description: description,
      part_number: part_number,
      unit:        unit,
      unit_price:  price&.public_price || 0,
      tax_rate:    price&.tax_rate || 0
    }
  end
end

