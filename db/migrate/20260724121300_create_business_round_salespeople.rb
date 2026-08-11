class CreateBusinessRoundSalespeople < ActiveRecord::Migration[8.1]
  def change
    # Vendedores asignados a la rueda (cnf_rueda_negocios_vendedor).
    create_table :business_round_salespeople, id: false do |t|
      t.references :business_round, null: false, foreign_key: true
      t.references :salesperson,    null: false, foreign_key: true
    end

    add_index :business_round_salespeople, [ :business_round_id, :salesperson_id ],
              unique: true, name: "idx_brsp_round_salesperson"
  end
end
