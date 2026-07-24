class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.integer :erp_product_id, null: false          # com_producto.id_producto (Código FECEGO = SKU oficial)
      t.string  :description                           # Descripción (nombre_publico / descripcion_corta)
      t.string  :part_number                           # Número de parte (numero_parte)
      t.string  :unit                                  # Unidad de medida (texto de cnf_unidad_medida)
      t.decimal :min_sale_quantity, precision: 14, scale: 3  # Mínimo de venta
      t.decimal :max_discount, precision: 5,  scale: 2       # Descuento tope (%)
      t.decimal :stock, precision: 14, scale: 2         # Existencia (la misma que se envía al vendedor)
      t.references :brand, foreign_key: true, null: true # Marca

      t.timestamps
    end

    add_index :products, :erp_product_id, unique: true
  end
end
