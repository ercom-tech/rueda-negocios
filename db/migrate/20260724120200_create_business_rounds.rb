class CreateBusinessRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :business_rounds do |t|
      t.integer :erp_round_id, null: false     # cnf_rueda_negocios.id_rueda
      t.string  :name, null: false
      t.integer :year
      t.date    :starts_on
      t.date    :ends_on
      t.string  :location                      # sede (país/estado/municipio, denormalizado)
      t.boolean :active, null: false, default: false  # la rueda activa en esta laptop

      t.timestamps
    end

    add_index :business_rounds, :erp_round_id, unique: true
  end
end
