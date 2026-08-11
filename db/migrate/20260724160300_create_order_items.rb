class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    # Partida del pedido. Snapshot de los datos del producto al momento de
    # agregarlo (para que el pedido no cambie si el catálogo cambia).
    create_table :order_items do |t|
      t.references :order,   null: false, foreign_key: true
      t.references :product, null: true,  foreign_key: true
      t.integer :position, null: false, default: 1  # consecutivo
      t.string  :code          # código FECEGO (snapshot)
      t.string  :description
      t.string  :part_number
      t.string  :unit
      t.decimal :quantity,         precision: 14, scale: 3, null: false, default: 1
      t.decimal :unit_price,       precision: 14, scale: 4, null: false, default: 0
      t.decimal :discount_percent, precision: 5,  scale: 2, null: false, default: 0
      t.decimal :tax_rate,         precision: 5,  scale: 2, null: false, default: 0  # IVA (snapshot)

      t.timestamps
    end

    add_index :order_items, [ :order_id, :position ]
  end
end
