class AddPromotionFieldsToOrderItems < ActiveRecord::Migration[8.1]
  def change
    # Qué promoción y qué escalón aplicaron a esta partida (→ id_promocion y
    # consec_promo del ERP). Nulos mientras no se aplique ninguna.
    add_reference :order_items, :promotion,      foreign_key: true, null: true
    add_reference :order_items, :promotion_tier, foreign_key: true, null: true

    # Partida que el sistema agregó como regalo de un escalón: solo lectura,
    # no cuenta contra el tope de partidas y se marca como regalo en la
    # pantalla y en el PDF.
    add_column :order_items, :gift, :boolean, default: false, null: false

    # El % que dictó la promoción, que el ERP guarda APARTE del aplicado
    # (vta_pedido_detalle.promo_porcentaje vs descto_porcentaje). Hoy salen
    # iguales; la columna existe porque el contrato del ERP los separa.
    add_column :order_items, :promotion_discount_percent, :decimal, precision: 5, scale: 2

    # El descuento que el capturista había tecleado y que la promoción pisó,
    # para devolvérselo al desaplicar (decisión del usuario 2026-08-22).
    # NUNCA viaja al ERP: el payload manda siempre `discount_percent`, el
    # efectivo. Es memoria de la laptop, no dato del pedido.
    add_column :order_items, :manual_discount_percent, :decimal, precision: 5, scale: 2
  end
end
