# Precios cargados desde un archivo en el panel del servidor (2026-10-08): el
# personal de la rueda cambia el precio unitario sin tocar el ERP ni volver a
# obtener la información.
#
# Va por CÓDIGO (`erp_product_id`) y rueda (`erp_round_id`), sin llave foránea
# a `products`: "Obtener información" borra y recrea el catálogo —los ids
# locales cambian— y esta tabla tiene que sobrevivirle. "Cerrar rueda" la
# vacía: son precios de ESA rueda.
#
# `loaded_by` es el username y no un FK a `users`: el sync-down también
# reemplaza usuarios.
class CreatePriceOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :price_overrides do |t|
      t.integer :erp_round_id, null: false
      t.integer :erp_product_id, null: false
      t.decimal :unit_price, precision: 14, scale: 2, null: false
      t.string :source_filename
      t.string :loaded_by
      t.timestamps
    end
    add_index :price_overrides, %i[erp_round_id erp_product_id], unique: true
    add_check_constraint :price_overrides, "unit_price > 0", name: "price_overrides_unit_price_positive"
  end
end
