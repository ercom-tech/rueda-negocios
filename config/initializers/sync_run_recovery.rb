# El bloque `server` corre SOLO cuando bootea el servidor web (no en consola,
# runner, rake ni tests): en esos otros procesos un run `running` puede ser
# legítimo (el server sigue vivo ejecutando su job) y barrerlo sería incorrecto.
# Además, solo con el adapter de jobs EN PROCESO (`async` en la laptop): ahí un
# reinicio del servidor sí mata cualquier job en vuelo, así que un `running` es
# siempre huérfano. Con un worker aparte (`solid_queue` en producción) la
# corrida puede seguir viva: barrerla la marcaría "interrumpida" y de paso
# liberaría la guarda de "una corrida a la vez", habilitando lanzar otra encima.
EN_PROCESO = %i[async inline test].freeze

Rails.application.server do
  next unless EN_PROCESO.include?(Rails.application.config.active_job.queue_adapter)

  SyncRun.recover_orphaned!
rescue ActiveRecord::ActiveRecordError => e
  # BD aún no creada/migrada (primer arranque): no impedir el boot.
  Rails.logger.warn("sync_run_recovery: #{e.message}")
end
