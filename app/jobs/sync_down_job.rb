class SyncDownJob < ApplicationJob
  queue_as :default

  # Descarga el dataset de la rueda seleccionada y puebla el Postgres local
  # (replace). Reporta el avance en el SyncRun asociado.
  def perform(sync_run_id)
    run = SyncRun.find(sync_run_id)
    # Mismas dos guardas que SyncUpJob (6ª auditoría): no correr sobre una
    # corrida que el barrido ya cerró, y registrar al ejecutor como dueño.
    return unless run.running?

    run.update!(pid: Process.pid)
    round_id = Setting.instance.selected_round_erp_id
    raise Sync::ApiClient::Error, "no hay una rueda seleccionada" if round_id.blank?

    data   = Sync::ApiClient.new.fetch_export(round_id)
    result = ActiveRecord::Base.transaction { Sync::Down.new(data).run! }

    run.finish!(status: :completed, summary: result.summary)
  rescue Sync::Down::GuardError, Sync::ApiClient::Error => e
    run&.finish!(status: :failed, message: e.message)
  rescue StandardError => e
    # El detalle técnico (clase, rutas internas, IPs de la red on-prem) va al
    # log; en el panel, guía accionable — mismo criterio que el resto del panel.
    Rails.logger.error(e.full_message)
    run&.finish!(status: :failed, message: "No se pudo obtener la información. Revisa que el servidor esté disponible e inténtalo de nuevo.")
    raise
  ensure
    # Espejo del rake (6ª auditoría): las excepciones fuera de StandardError
    # dejaban la corrida running con dueño vivo hasta reiniciar el servicio.
    run.finish_interrupted! if run&.running?
  end
end
