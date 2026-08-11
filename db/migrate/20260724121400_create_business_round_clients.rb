class CreateBusinessRoundClients < ActiveRecord::Migration[8.1]
  def change
    # Clientes registrados en la rueda con flujo de aprobación
    # (cnf_rueda_negocios_cliente). Modelo de unión: carga banderas y crédito.
    create_table :business_round_clients do |t|
      t.references :business_round, null: false, foreign_key: true
      t.references :client,         null: false, foreign_key: true
      t.references :salesperson,    null: true,  foreign_key: true  # vendedor que registró al cliente
      t.boolean :approved_sales,  null: false, default: false
      t.boolean :approved_credit, null: false, default: false
      t.decimal :authorized_credit_limit, precision: 14, scale: 2

      t.timestamps
    end

    add_index :business_round_clients, [ :business_round_id, :client_id ],
              unique: true, name: "idx_brc_round_client"
  end
end
