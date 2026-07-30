class CreateDivideAmounts < ActiveRecord::Migration[8.1]
  # Catálogo de montos de división de facturas (vta_pedido_monto_divide):
  # opciones del combo "Dividir facturas cada ($)" del paso 1.
  def change
    create_table :divide_amounts do |t|
      t.integer :erp_consecutive, null: false
      t.decimal :amount, precision: 18, scale: 6, null: false

      t.timestamps
    end
    add_index :divide_amounts, :erp_consecutive, unique: true
  end
end
