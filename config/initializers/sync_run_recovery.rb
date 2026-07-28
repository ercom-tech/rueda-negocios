# El bloque `server` corre SOLO cuando bootea el servidor web (no en consola,
# runner, rake ni tests): en esos otros procesos un run `running` puede ser
# legítimo (el server sigue vivo ejecutando su job) y barrerlo sería incorrecto.
Rails.application.server do
  SyncRun.recover_orphaned!
rescue ActiveRecord::ActiveRecordError => e
  # BD aún no creada/migrada (primer arranque): no impedir el boot.
  Rails.logger.warn("sync_run_recovery: #{e.message}")
end
