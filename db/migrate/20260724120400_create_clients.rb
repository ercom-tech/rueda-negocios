class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string  :erp_client_key, null: false   # vta_cliente.clave_cliente
      t.string  :name
      t.string  :commercial_name
      t.decimal :credit_limit, precision: 14, scale: 2
      t.integer :credit_days
      t.boolean :approved, null: false, default: false
      t.references :salesperson, foreign_key: true, null: true

      t.timestamps
    end

    add_index :clients, :erp_client_key, unique: true
  end
end
