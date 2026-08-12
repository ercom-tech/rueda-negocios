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
  # La rama del código compara contra el código PADDED a 6 dígitos (como lo
  # muestra el ERP y lo teclea la gente): "000081" solo puede coincidir con el
  # código exacto 000081 (6 dentro de 6 = igualdad), "17768" sigue hallando a
  # 017768 y "0177" a los 0177xx. Normalizar quitando ceros ("000081"→"81")
  # resultó engañoso: "81" está contenido en 003381, 004817, etc. El índice
  # trigram de expresión sobre el LPAD mantiene la rama indexada.
  scope :search, ->(query) {
    q    = sanitize_sql_like(query.to_s.strip)
    like = "%#{q}%"
    # Rango de relevancia + orden estable (espejo de Client.search): sin
    # ORDER BY, Postgres devolvía el top-10 del autocompletado en orden
    # arbitrario — con >10 coincidencias el producto buscado podía no
    # aparecer, y la lista cambiaba entre teclas sin cambiar el criterio.
    relevance = sanitize_sql_array([
      "CASE WHEN LPAD(CAST(products.erp_product_id AS TEXT), 6, '0') ILIKE :p " \
      "OR products.description ILIKE :p THEN 0 ELSE 1 END, products.description, products.id",
      { p: "#{q}%" }
    ])
    where(<<~SQL, q: like).order(Arel.sql(relevance))
      products.id IN (
        SELECT id FROM products
         WHERE LPAD(CAST(erp_product_id AS TEXT), 6, '0') ILIKE :q
            OR description ILIKE :q
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
