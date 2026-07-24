class CreateBusinessRoundBrands < ActiveRecord::Migration[8.1]
  def change
    # Marcas participantes en la rueda (cnf_rueda_negocios_marca).
    create_table :business_round_brands, id: false do |t|
      t.references :business_round, null: false, foreign_key: true
      t.references :brand,          null: false, foreign_key: true
    end

    add_index :business_round_brands, [:business_round_id, :brand_id],
              unique: true, name: "idx_brb_round_brand"
  end
end
