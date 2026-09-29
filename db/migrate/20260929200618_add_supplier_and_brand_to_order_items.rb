# A quién pertenece un producto nuevo (genérico 999999). Lo elige el
# capturista al agregarlo, entre sus proveedores y marcas asignados en la rueda
# (2026-09-29). Una de las dos columnas o ninguna: las partidas de catálogo ya
# saben su proveedor y su marca por el producto, y las del genérico anteriores
# a este cambio no la tienen.
#
# Se queda en la laptop: el detalle del pedido del ERP no tiene dónde
# guardarlo (decisión del usuario: sirve para los reportes del evento).
#
# Llave foránea sin riesgo para el reemplazo del catálogo: el sync-down borra
# proveedores y marcas solo después de purgar los pedidos transmitidos, y se
# niega a correr si queda cualquier otro pedido en la laptop.
class AddSupplierAndBrandToOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_reference :order_items, :supplier, foreign_key: true, null: true
    add_reference :order_items, :brand, foreign_key: true, null: true
  end
end
