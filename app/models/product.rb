class Product < ApplicationRecord
  # Producto (com_producto). erp_product_id es el Código FECEGO (SKU oficial).

  belongs_to :brand, optional: true

  has_one :price, dependent: :destroy

  # Código FECEGO del producto "fuera de catálogo" ("AJUSTE DE MERCANCIA" en
  # el ERP): cualquier capturista puede usarlo, sin membresía de proveedor ni
  # marca, capturando descripción, no. de parte y precio a mano (decisión
  # FECEGO 2026-08-17). El ERP nativo lo maneja igual: precio libre y el
  # texto en vta_pedido_detalle.nombre_capturado.
  GENERIC_ERP_ID = 999_999

  def generic?
    erp_product_id == GENERIC_ERP_ID
  end

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

  # Cuántas sugerencias devuelve el buscador. Era 10 y se quedaba corto en casi
  # todo: sobre el catálogo real de la rueda, "LIJA" da 256 coincidencias,
  # "TORNILLO" 228, "LLAVE" 178 y "CABLE" 113.
  #
  # El recorte de "se cortaban casi siempre", que antes faltaba: contando
  # productos distintos por palabra de 4+ letras de la descripción, el 90% de
  # las 1,000 palabras MÁS FRECUENTES rebasa 10 coincidencias (sobre las 12,166
  # distintas del catálogo, que incluyen las que nadie teclea, es el 7.4%).
  #
  # El costo del tope es irrelevante —la consulta ya recorre todo y el límite
  # solo corta la salida—, así que lo que manda es cuánto se puede recorrer en
  # una tablet. (Aquí iban dos tiempos concretos, 0.8 ms y 2.1 ms; medidos de
  # nuevo no se reproducen y además se contradecían con la frase que
  # ilustraban: si el límite solo corta la salida, no puede haber un salto de
  # 2.6×. La diferencia real entre topes es ruido. 8ª auditoría.)
  #
  # Ningún tope razonable cubre "LIJA": lo que saca del apuro es el aviso de
  # que hay más (ver `_product_options`).
  SEARCH_LIMIT = 50

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
      # Crédito mayoreo (decisión FECEGO 2026-08-17): el nivel al que vende
      # la rueda. Un producto con crédito mayoreo en $0 en el ERP queda
      # invendible con aviso ("producto sin precio") — el dato se corrige
      # allá, que es su dueño; no hay fallback a otro nivel.
      unit_price:  price&.credit_wholesale_price || 0,
      tax_rate:    price&.tax_rate || 0
    }
  end
end
