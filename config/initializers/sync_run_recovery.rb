# El bloque `server` corre SOLO cuando bootea el servidor web (no en consola,
# runner, rake ni tests). El barrido respeta cualquier corrida cuyo proceso
# dueño siga vivo (`SyncRun#owner_alive?`, por pid) — una tarea rake en otra
# terminal o un worker aparte no se marcan "interrumpidos" — así que es seguro
# con cualquier adapter de jobs. También re-corre al cargar el menú del
# servidor (HomeController), para que una corrida muerta se recupere sin
# reiniciar el servicio.
Rails.application.server do
  SyncRun.recover_orphaned!
rescue ActiveRecord::ActiveRecordError => e
  # BD aún no creada/migrada (primer arranque): no impedir el boot.
  Rails.logger.warn("sync_run_recovery: #{e.message}")
end
