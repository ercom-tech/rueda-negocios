class CreateBrandsSuppliers < ActiveRecord::Migration[8.1]
  def change
    # Proveedor ↔ marca (com_proveedor_has_marca). Puente puro (HABTM).
    create_table :brands_suppliers, id: false do |t|
      t.references :brand,    null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true
    end

    add_index :brands_suppliers, [ :brand_id, :supplier_id ], unique: true
  end
end
