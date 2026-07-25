class AddTaxRateToPrices < ActiveRecord::Migration[8.1]
  def change
    # IVA aplicable (porcentaje, ej. 16.00). Viene de com_producto_has_precio.iva.
    add_column :prices, :tax_rate, :decimal, precision: 5, scale: 2
  end
end
