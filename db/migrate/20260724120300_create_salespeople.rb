class CreateSalespeople < ActiveRecord::Migration[8.1]
  def change
    create_table :salespeople do |t|
      t.integer :erp_salesperson_id, null: false  # vta_vendedor.id_vendedor
      t.string  :name
      t.integer :erp_person_id                     # vta_vendedor.id_persona (puede ser 0/nil)

      t.timestamps
    end

    add_index :salespeople, :erp_salesperson_id, unique: true
  end
end
