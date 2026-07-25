class SyncRun < ApplicationRecord
  # Registro de una corrida de sync (down/up). El job la crea en `running`,
  # y la cierra en `completed` o `failed` con su resumen. El panel del servidor
  # muestra el estado del último run de cada tipo.

  enum :kind,   { down: "down", up: "up" }
  enum :status, { running: "running", completed: "completed", failed: "failed" }

  scope :recent_first, -> { order(created_at: :desc) }

  # Refresca el panel del servidor en vivo cuando el job cierra el run.
  after_update_commit do
    broadcast_replace_to "sync_status", target: "sync-#{kind}-status",
                         partial: "server/sync_status", locals: { run: self }
  end

  # Último run de un tipo (down/up).
  def self.latest(kind)
    where(kind: kind).recent_first.first
  end

  def finish!(status:, summary: {}, message: nil)
    update!(status: status, summary: summary, message: message, finished_at: Time.current)
  end

  def duration
    return nil unless started_at && finished_at

    finished_at - started_at
  end
end
