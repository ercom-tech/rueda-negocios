class CreateProductSuppliers < ActiveRecord::Migration[8.1]
  def change
    # Producto ↔ proveedor (com_proveedor_has_producto). Modelo de unión porque
    # carga el SKU del proveedor (com_producto_has_sku), distinto por proveedor.
    create_table :product_suppliers do |t|
      t.references :product,  null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true
      t.string     :supplier_sku   # SKU del proveedor

      t.timestamps
    end

    add_index :product_suppliers, [ :product_id, :supplier_id ], unique: true
  end
end
