class AddCreditWholesalePriceToPrices < ActiveRecord::Migration[8.1]
  # El precio que la rueda cobra (decisión FECEGO 2026-08-17): crédito
  # mayoreo (`com_producto_has_precio.cred_mayoreo_precio`). Público y
  # mayoreo se conservan como referencia.
  def change
    add_column :prices, :credit_wholesale_price, :decimal, precision: 14, scale: 4
  end
end
