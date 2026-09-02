# Piezas vendidas por producto en la rueda, para el reporte de productos.
#
# Se construye SOBRE un scope de pedidos ya acotado por rol
# (`accessible_orders`), así que un capturista nunca puede sumar pedidos
# ajenos: el filtro de proveedor/marca se aplica encima, nunca en su lugar.
#
# Solo cuentan los pedidos CAPTURADOS y TRANSMITIDOS. Un borrador no es venta
# y además cambia mientras se captura: contarlo haría que el reporte se moviera
# solo entre dos consultas.
#
# Vendido y regalado van en columnas SEPARADAS (decisión del usuario
# 2026-09-02): las dos son piezas que salen del almacén, pero mezclarlas
# escondería cuánto se bonificó dentro de lo que se cobró.
class ProductSales
  Row = Struct.new(:code, :description, :model, :part_number, :sold, :gifted, :sku,
                   keyword_init: true)

  # Las dos mitades del mismo SUM: `gift` parte las piezas en cobradas y
  # bonificadas sin necesitar dos consultas.
  SOLD_SQL   = "COALESCE(SUM(CASE WHEN order_items.gift THEN 0 ELSE order_items.quantity END), 0)".freeze
  GIFTED_SQL = "COALESCE(SUM(CASE WHEN order_items.gift THEN order_items.quantity ELSE 0 END), 0)".freeze

  def initialize(orders, supplier_id: nil, brand_id: nil)
    @orders      = orders.where(status: %w[captured transmitted])
    @supplier_id = supplier_id
    @brand_id    = brand_id
  end

  # ¿Hay algún filtro de proveedor o marca activo? De esto depende que el
  # bloque del genérico se muestre o se anuncie (ver `generic_rows`).
  def filtered?
    @supplier_id.present? || @brand_id.present?
  end

  # Productos del catálogo, más vendidos primero.
  def catalog_rows
    @catalog_rows ||= begin
      totals = items.where(product_id: catalog_products.select(:id))
                    .group(:product_id)
                    .pluck(:product_id, Arel.sql(SOLD_SQL), Arel.sql(GIFTED_SQL))
      build_rows(totals)
    end
  end

  # Fuera de catálogo (999999), agrupado por lo que el capturista TECLEÓ, no
  # por producto: el genérico es un solo `product_id` con tantas descripciones
  # como cosas se hayan vendido con él, así que agruparlo por producto daría un
  # renglón que suma peras con manzanas. El texto ya viene normalizado
  # (`squish.upcase` en OrderItem#normalize_generic_fields), así que
  # "martillo  x" y "MARTILLO X " caen en el mismo renglón.
  #
  # No pertenece a ningún proveedor ni marca, así que con un filtro activo NO
  # aparece: contaminaría el total de un proveedor con venta que no es suya.
  def generic_rows
    return [] if filtered?

    @generic_rows ||=
      generic_items.group(:description, :part_number)
                   .pluck(:description, :part_number, Arel.sql(SOLD_SQL), Arel.sql(GIFTED_SQL))
                   .map do |description, part_number, sold, gifted|
                     Row.new(code: format("%06d", Product::GENERIC_ERP_ID), description: description,
                             model: nil, part_number: part_number,
                             sold: sold, gifted: gifted, sku: nil)
                   end
                   .sort_by { |r| [ -r.sold, r.description.to_s ] }
  end

  # Piezas del genérico que el filtro está dejando fuera. Se anuncia en
  # pantalla: sin eso, un reporte filtrado se lee como "esto fue todo lo que se
  # vendió" y el fuera de catálogo desaparece sin dejar rastro.
  def hidden_generic_quantity
    return 0 unless filtered?

    @hidden_generic_quantity ||= generic_items.sum(:quantity)
  end

  private

  def items
    OrderItem.where(order_id: @orders.select(:id))
  end

  def generic_items
    items.where(product_id: Product.where(erp_product_id: Product::GENERIC_ERP_ID).select(:id))
  end

  # El universo de productos que el filtro autoriza. El genérico queda fuera
  # siempre: no tiene marca, modelo ni SKU, y se reporta aparte.
  def catalog_products
    scope = Product.where.not(erp_product_id: Product::GENERIC_ERP_ID)
    scope = scope.where(brand_id: @brand_id) if @brand_id.present?
    if @supplier_id.present?
      scope = scope.where(id: ProductSupplier.where(supplier_id: @supplier_id).select(:product_id))
    end
    scope
  end

  # Los datos del producto y sus SKUs se piden en DOS consultas y se cruzan en
  # memoria, no con un JOIN: `product_suppliers` tiene una fila por proveedor,
  # así que unirla al agregado duplicaría el renglón de un producto que venden
  # dos proveedores — y con él, su cantidad.
  def build_rows(totals)
    products = Product.where(id: totals.map(&:first)).index_by(&:id)
    skus     = skus_for(totals.map(&:first))

    totals.filter_map do |product_id, sold, gifted|
      product = products[product_id]
      next unless product

      Row.new(code: product.erp_code, description: product.description,
              model: product.model, part_number: product.part_number,
              sold: sold, gifted: gifted, sku: skus[product_id])
    end.sort_by { |r| [ -r.sold, r.description.to_s ] }
  end

  # Con un proveedor filtrado, su SKU. Sin filtro, todos los que tenga —
  # normalmente uno; separados por coma cuando de verdad son varios.
  def skus_for(product_ids)
    scope = ProductSupplier.where(product_id: product_ids).where.not(supplier_sku: [ nil, "" ])
    scope = scope.where(supplier_id: @supplier_id) if @supplier_id.present?
    scope.pluck(:product_id, :supplier_sku)
         .group_by(&:first)
         .transform_values { |pairs| pairs.map(&:last).uniq.sort.join(", ") }
  end
end
