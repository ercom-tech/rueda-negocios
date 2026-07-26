class Product < ApplicationRecord
  # Producto (com_producto). erp_product_id es el Código FECEGO (SKU oficial).

  belongs_to :brand, optional: true

  has_one :price, dependent: :destroy

  has_many :product_suppliers, dependent: :destroy
  has_many :suppliers, through: :product_suppliers

  validates :erp_product_id, presence: true, uniqueness: true

  # Búsqueda por código FECEGO, código de proveedor (SKU), nombre, modelo o
  # número de parte. El SKU va en una rama UNION aparte (no en el mismo OR con
  # LEFT JOIN): un OR que cruza el join impide usar índices por tabla; así cada
  # rama entra por su índice trigram (BitmapOr en products, GIN en supplier_sku).
  scope :search, ->(query) {
    like = "%#{sanitize_sql_like(query.to_s.strip)}%"
    where(<<~SQL, q: like)
      products.id IN (
        SELECT id FROM products
         WHERE CAST(erp_product_id AS TEXT) ILIKE :q OR description ILIKE :q
            OR model ILIKE :q OR part_number ILIKE :q
        UNION
        SELECT product_id FROM product_suppliers WHERE supplier_sku ILIKE :q
      )
    SQL
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

