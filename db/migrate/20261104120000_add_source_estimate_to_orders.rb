class AddSourceEstimateToOrders < ActiveRecord::Migration[8.1]
  # El pedido que nace de "Convertir en pedido" recuerda la cotización de la
  # que salió (decisión del usuario 2026-11-04, 18ª auditoría): la cotización
  # se borra al convertirse, y sin esto la evidencia del ERP mostraba el pedido
  # capturado de un golpe — nada explicaba un precio anterior a un "Cambiar
  # precios". Viaja en el paquete como `cotizacion_origen`.
  #
  # Nullable las dos, sin default: un pedido capturado directo no tiene
  # cotización de origen, y el código anterior las ignora (revertir con
  # `git checkout` no necesita rollback, como las del 2026-09-29).
  def change
    add_column :orders, :source_estimate_folio, :string
    add_column :orders, :source_estimate_created_at, :datetime
  end
end
