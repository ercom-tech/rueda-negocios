class SyncRun < ApplicationRecord
  # Registro de una corrida de sync (down/up). El job la crea en `running`,
  # y la cierra en `completed` o `failed` con su resumen. El panel del servidor
  # muestra el estado del último run de cada tipo.

  enum :kind,   { down: "down", up: "up" }
  enum :status, { running: "running", completed: "completed", failed: "failed" }

  scope :recent_first, -> { order(created_at: :desc) }

  # Refresca el panel del servidor en vivo cuando el job cierra el run. Se
  # reemplaza el menú COMPLETO (no solo la línea de estado): los botones
  # bloqueados por "corrida en curso" deben rehabilitarse sin recargar.
  after_update_commit do
    broadcast_replace_to "sync_status", target: "server-menu",
                         partial: "home/server_menu",
                         locals: { setting:   Setting.instance,
                                   sync_down: SyncRun.latest("down"),
                                   sync_up:   SyncRun.latest("up") }
  end

  # Último run de un tipo (down/up).
  def self.latest(kind)
    where(kind: kind).recent_first.first
  end

  # Llave del lock que serializa "¿hay una corrida viva?" + el alta.
  LOCK_KEY = "rueda-negocios:sync".freeze

  # Corre el bloque con exclusión mutua REAL entre corridas de cualquier tipo.
  #
  # El índice único de respaldo (`index_sync_runs_one_running_per_kind`) es
  # **por tipo**: garantiza un solo `down` vivo y un solo `up` vivo, pero NO
  # impide que coexistan uno de cada uno. Sin este lock, dos peticiones casi
  # simultáneas pasan ambas el `running.exists?` (todavía no hay filas) e
  # insertan sin violar el índice — y entonces el replace del sync-down borra
  # los pedidos que el sync-up está transmitiendo: el pedido entra al ERP pero
  # el `update!` del folio escribe sobre una fila ya borrada, sin excepción, y
  # el folio se pierde. Mismo riesgo al cerrar la rueda contra un job vivo.
  #
  # `pg_advisory_xact_lock` se libera solo al terminar la transacción.
  def self.exclusively
    transaction do
      connection.select_value(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtext(?))", LOCK_KEY ]))
      yield
    end
  end

  # Crea la corrida solo si no hay ninguna viva; nil si ya había una.
  def self.start(kind)
    exclusively do
      next nil if running.exists?

      create!(kind: kind, started_at: Time.current)
    end
  end

  # Marca como fallidos los runs huérfanos: quedaron `running` porque el
  # proceso murió a media corrida (apagón, cierre del server). Se invoca al
  # bootear el servidor — con el adapter de jobs en proceso, ningún job
  # sobrevive a un reinicio, así que un `running` en ese momento es siempre
  # un huérfano. Sin esta barrida, el renglón congelado deja el panel girando
  # "en progreso" para siempre y su guard bloquea nuevas corridas.
  def self.recover_orphaned!
    running.find_each do |run|
      run.finish!(status: :failed, message: "Interrumpido: el servidor se reinició a media corrida")
    end
  end

  def finish!(status:, summary: {}, message: nil)
    update!(status: status, summary: summary, message: message, finished_at: Time.current)
  end

  def duration
    return nil unless started_at && finished_at

    finished_at - started_at
  end
end
