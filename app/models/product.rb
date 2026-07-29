class Product < ApplicationRecord
  # Producto (com_producto). erp_product_id es el Código FECEGO (SKU oficial).

  belongs_to :brand, optional: true

  has_one :price, dependent: :destroy

  has_many :product_suppliers, dependent: :destroy
  has_many :suppliers, through: :product_suppliers

  validates :erp_product_id, presence: true, uniqueness: true

  # Código FECEGO como lo muestra el ERP: entero presentado SIEMPRE a 6
  # dígitos (17768 → "017768"). Única definición del formato — se usa en
  # autocompletado y en el snapshot de partidas (tabla/resumen/PDF).
  def erp_code
    format("%06d", erp_product_id)
  end

  # Búsqueda por código FECEGO, código de proveedor (SKU), nombre, modelo o
  # número de parte. El SKU va en una rama UNION aparte (no en el mismo OR con
  # LEFT JOIN): un OR que cruza el join impide usar índices por tabla; así cada
  # rama entra por su índice trigram (BitmapOr en products, GIN en supplier_sku).
  #
  # El código FECEGO se muestra a 6 dígitos, así que "017768" debe encontrar
  # al entero 17768: a una consulta de puro dígito se le quitan los ceros a la
  # izquierda SOLO para la rama del código (normalizar aquí conserva el plan
  # con índices; un LPAD(...) ILIKE los brincaría). Las demás ramas reciben la
  # cadena original — un número de parte sí puede empezar con 0 legítimo.
  scope :search, ->(query) {
    raw  = query.to_s.strip
    code = raw.match?(/\A\d+\z/) ? raw.sub(/\A0+/, "") : raw
    code = raw if code.empty? # "000000" no debe degenerar en match-todo
    like      = "%#{sanitize_sql_like(raw)}%"
    code_like = "%#{sanitize_sql_like(code)}%"
    where(<<~SQL, q: like, qcode: code_like)
      products.id IN (
        SELECT id FROM products
         WHERE CAST(erp_product_id AS TEXT) ILIKE :qcode OR description ILIKE :q
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
      code:        erp_code,
      description: description,
      part_number: part_number,
      unit:        unit,
      unit_price:  price&.public_price || 0,
      tax_rate:    price&.tax_rate || 0
    }
  end
end

