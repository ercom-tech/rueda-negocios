class CreateClientBranches < ActiveRecord::Migration[8.1]
  def change
    # Sucursal / dirección de entrega del cliente. Un cliente puede tener varias.
    create_table :client_branches do |t|
      t.references :client, null: false, foreign_key: true
      t.integer :erp_branch_id
      t.string  :name
      t.string  :address
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :client_branches, :erp_branch_id
  end
end
