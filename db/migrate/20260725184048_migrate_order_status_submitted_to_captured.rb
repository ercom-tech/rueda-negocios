class MigrateOrderStatusSubmittedToCaptured < ActiveRecord::Migration[8.1]
  # Renombramos el estatus "submitted" (Enviado) a "captured" (Capturado). Los
  # ya transmitidos (con erp_folio) pasan a "transmitted". SQL directo para no
  # depender del enum del modelo.
  def up
    execute "UPDATE orders SET status = 'transmitted' WHERE status = 'submitted' AND erp_folio IS NOT NULL"
    execute "UPDATE orders SET status = 'captured'    WHERE status = 'submitted'"
  end

  def down
    execute "UPDATE orders SET status = 'submitted' WHERE status IN ('captured', 'transmitted')"
  end
end
