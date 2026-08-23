class CreatePromotions < ActiveRecord::Migration[8.1]
  # Espejo local de las promociones de la rueda (vta_promocion y sus tres
  # tablas hijas, canal_venta = 'RUN'). Se repuebla completo en cada
  # sync-down, igual que el resto del catálogo.
  def change
    create_table :promotions do |t|
      t.integer :erp_promotion_id, null: false
      t.string  :code
      t.string  :name
      t.date    :starts_on
      t.date    :ends_on
      t.timestamps
      t.index :erp_promotion_id, unique: true
    end

    # Los escalones: cuánto se descuenta según cuánto se compre del universo.
    # `condition_kind`: CE = "en la compra de entre X y Y" · CM = "en la
    # compra mínima de X" (quantity_to llega en 0) · PC = "por cada X".
    # `unit`: MXN mide importe, PZA mide piezas.
    create_table :promotion_tiers do |t|
      t.references :promotion, null: false, foreign_key: true
      t.integer :erp_consecutive, null: false
      t.string  :condition_kind
      t.string  :unit
      t.decimal :quantity_from,    precision: 18, scale: 6, default: 0, null: false
      t.decimal :quantity_to,      precision: 18, scale: 6, default: 0, null: false
      t.decimal :discount_percent, precision: 5,  scale: 2, default: 0, null: false
      t.timestamps
      t.index %i[promotion_id erp_consecutive], unique: true
    end

    # El universo: qué productos participan. `discount_percent` por renglón
    # es un OVERRIDE que gana sobre el escalón (FANAL lleva su escalón en 0%
    # y el descuento real en cada uno de sus 57 códigos).
    #
    # El índice por producto es el que sostiene la flama: la tabla de
    # partidas pregunta "¿este producto tiene promoción?" en cada repintado,
    # y son 6,046 renglones × 45 filas.
    create_table :promotion_products do |t|
      t.references :promotion, null: false, foreign_key: true
      t.references :product,   null: false, foreign_key: true
      t.decimal :discount_percent, precision: 5, scale: 2, default: 0, null: false
      t.timestamps
      t.index %i[promotion_id product_id], unique: true
    end

    # Qué se regala al alcanzar un escalón. Cuelga del ESCALÓN, no de la
    # promoción: FANDELI regala solo en el de $20,000 y no en los de abajo.
    create_table :promotion_gifts do |t|
      t.references :promotion_tier, null: false, foreign_key: true
      t.references :product,        null: false, foreign_key: true
      t.decimal :quantity, precision: 18, scale: 6, default: 1, null: false
      t.timestamps
    end
  end
end
