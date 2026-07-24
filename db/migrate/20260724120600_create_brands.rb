class CreateBrands < ActiveRecord::Migration[8.1]
  def change
    create_table :brands do |t|
      t.integer :erp_brand_id, null: false     # com_marca.id_marca
      t.string  :name
      t.string  :code                          # com_marca.clave

      t.timestamps
    end

    add_index :brands, :erp_brand_id, unique: true
  end
end
