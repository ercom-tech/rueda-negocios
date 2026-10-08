# De dónde salió el precio de la partida (2026-10-08): del ERP o de un archivo
# de precios cargado en el panel del servidor. Se fija al AGREGAR la partida,
# como el resto del snapshot: un archivo que se cargue o se quite después no
# reescribe la historia de la partida.
#
# `erp_unit_price` es el crédito mayoreo del ERP en ese momento, solo cuando el
# archivo lo reemplazó: viaja a la evidencia del ERP (dentro del `payload`)
# para que meses después se vea que el precio no fue el de lista.
class AddPriceSourceToOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :order_items, :price_from_file, :boolean, default: false, null: false
    add_column :order_items, :erp_unit_price, :decimal, precision: 14, scale: 4
  end
end
