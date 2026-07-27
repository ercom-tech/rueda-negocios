class RemoveMinSaleQuantityFromProducts < ActiveRecord::Migration[8.1]
  # Columna muerta: nunca se pobló por el sync ni se usó en validación alguna.
  # Se evaluó cablearla como "venta solo en múltiplos de empaque"
  # (com_producto_has_empaque.minimo del ERP), pero ~20% de las partidas
  # reales del ERP NO son múltiplos — no es una regla dura del negocio.
  # Decisión del usuario (2ª auditoría, B3): eliminarla.
  def change
    remove_column :products, :min_sale_quantity, :decimal, precision: 14, scale: 3
  end
end
