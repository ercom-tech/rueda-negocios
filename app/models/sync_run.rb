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
