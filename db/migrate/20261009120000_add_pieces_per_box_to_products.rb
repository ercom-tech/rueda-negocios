# Piezas por caja de la ficha técnica del ERP (`alm_ficha_tecnica`, renglón
# tipo 'C'), para el Cotizador de la captura (2026-10-09). NULL = el ERP no
# tiene el dato, y el Cotizador muestra solo los precios por pieza.
class AddPiecesPerBoxToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :pieces_per_box, :decimal, precision: 18, scale: 6
  end
end
