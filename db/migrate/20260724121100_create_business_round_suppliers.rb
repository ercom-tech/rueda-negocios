class CreateBusinessRoundSuppliers < ActiveRecord::Migration[8.1]
  def change
    # Proveedores participantes en la rueda (cnf_rueda_negocios_proveedor).
    create_table :business_round_suppliers, id: false do |t|
      t.references :business_round, null: false, foreign_key: true
      t.references :supplier,       null: false, foreign_key: true
    end

    add_index :business_round_suppliers, [ :business_round_id, :supplier_id ],
              unique: true, name: "idx_brs_round_supplier"
  end
end
