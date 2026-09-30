# Cuándo guardó el capturista el pedido por última vez (2026-09-29). Viaja a la
# evidencia del ERP (`vta_pedido_rueda.guardado_en_laptop`) junto con
# `created_at`: lo que se capturó y CUÁNDO, para aclaraciones posteriores.
#
# Nullable: los pedidos guardados antes de esta columna no lo tienen, y la
# evidencia lo deja vacío en vez de inventarlo con `updated_at` (que cambia por
# cosas que no son guardar: aplicar una promoción, por ejemplo).
class AddCapturedAtToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :captured_at, :datetime
  end
end
