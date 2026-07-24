class CreateSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.integer :erp_supplier_id, null: false  # com_proveedor.id_proveedor
      t.string  :code                          # com_proveedor.clave (código legible)
      t.string  :name
      t.string  :commercial_name               # denominacion_comercial

      t.timestamps
    end

    add_index :suppliers, :erp_supplier_id, unique: true
  end
end
