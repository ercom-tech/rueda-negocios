class AddDividirFacturasToOrders < ActiveRecord::Migration[8.1]
  # Espejo de fecego.vta_pedido.dividir_facturas (NUMERIC(18,6), default 0):
  # importe máximo por factura al facturar el pedido; 0 = no dividir.
  def change
    add_column :orders, :dividir_facturas, :decimal, precision: 18, scale: 6,
               default: 0, null: false
  end
end
