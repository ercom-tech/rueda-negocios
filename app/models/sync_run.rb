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

  # Crea la corrida solo si no hay ninguna viva; nil si ya había una. El `pid`
  # identifica al proceso dueño: es lo que le permite al barrido de huérfanos
  # distinguir una corrida muerta de una tarea rake que sigue viva en otra
  # terminal.
  def self.start(kind)
    exclusively do
      next nil if running.exists?

      create!(kind: kind, started_at: Time.current, pid: Process.pid)
    end
  end

  # Marca como fallidos los runs huérfanos: quedaron `running` porque su
  # proceso murió a media corrida (apagón, kill, Ctrl-C a un rake). El dueño
  # se identifica por su `pid`: si sigue vivo —una tarea rake corriendo en
  # otra terminal, un worker aparte— la corrida se respeta, porque barrerla
  # la marcaría "interrumpida" y liberaría la guarda de "una corrida a la
  # vez" encima de un sync en curso. Sin esta barrida, el renglón congelado
  # deja el panel girando "en progreso" para siempre, la captura pausada y
  # "Cerrar rueda" bloqueado.
  def self.recover_orphaned!
    running.find_each do |run|
      next if run.owner_alive?

      run.finish_interrupted!
    end
  end

  # Cierre de una corrida cuyo proceso murió. En un sync-up, la advertencia
  # que todos los caminos de falla post-envío ya dan: sin ella, editar antes
  # del reintento llevaba a la colisión del 422 (6ª auditoría).
  def finish_interrupted!
    msg = "Interrumpido: la corrida se quedó a medias. Vuelve a intentar."
    msg += " Los pedidos pudieron haber entrado al ERP: vuelve a transmitir sin editarlos." if up?
    finish!(status: :failed, message: msg)
  end

  # ¿El proceso que abrió la corrida sigue vivo? La señal 0 no manda nada:
  # solo comprueba existencia. Una corrida sin pid (anterior a la columna) se
  # trata como huérfana. EPERM sería "vivo pero de otro usuario" — tratarlo
  # como vivo es el lado seguro para procesos NUESTROS; para los ajenos lo
  # resuelve el corte por boot de abajo.
  def owner_alive?
    return false if pid.blank?
    # Una corrida iniciada antes del boot actual tiene al dueño muerto por
    # definición: ningún proceso sobrevive un reinicio. Cubre el pid
    # reciclado por un daemon del arranque (a menudo de root → EPERM →
    # "vivo"), que dejaba la corrida respetada indefinidamente con la
    # captura pausada — el único caso donde reiniciar no curaba (6ª aud.).
    return false if started_at && started_at < self.class.booted_at

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  # Boot del sistema. Linux (la laptop): btime de /proc/stat; macOS (dev):
  # sysctl. Memoizado: el boot no cambia dentro del proceso.
  def self.booted_at
    @booted_at ||=
      if File.readable?("/proc/stat")
        Time.at(File.read("/proc/stat")[/^btime (\d+)/, 1].to_i)
      else
        Time.at(`sysctl -n kern.boottime`[/sec = (\d+)/, 1].to_i)
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
