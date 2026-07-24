class CreatePrices < ActiveRecord::Migration[8.1]
  def change
    create_table :prices do |t|
      # Un solo precio activo por producto (índice único en la referencia).
      t.references :product, null: false, foreign_key: true, index: { unique: true }
      t.decimal :public_price,    precision: 14, scale: 4  # Precio público
      t.decimal :wholesale_price, precision: 14, scale: 4  # Precio mayoreo

      t.timestamps
    end
  end
end
