class AddMinSaleQuantityToProducts < ActiveRecord::Migration[8.1]
  # Empaque mínimo de venta (com_producto_has_empaque, cantidad con
  # minimo=true): el producto solo se vende en múltiplos de este valor.
  # NULL = sin regla de empaque.
  def change
    add_column :products, :min_sale_quantity, :decimal, precision: 18, scale: 6
  end
end
