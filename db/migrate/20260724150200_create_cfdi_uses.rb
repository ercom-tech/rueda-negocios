class CreateCfdiUses < ActiveRecord::Migration[8.1]
  def change
    # Catálogo SAT de uso de CFDI (G01, G03, P01, …).
    create_table :cfdi_uses do |t|
      t.string :code, null: false
      t.string :description

      t.timestamps
    end

    add_index :cfdi_uses, :code, unique: true
  end
end
