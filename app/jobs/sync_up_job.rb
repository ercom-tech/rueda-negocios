class SyncUpJob < ApplicationJob
  queue_as :default

  # Transmite los pedidos capturados al ERP. Reporta el resultado en el SyncRun.
  # Si algún pedido falla, el run queda `failed` (transmisión parcial) con el
  # detalle en el resumen para reintentar.
  def perform(sync_run_id)
    run    = SyncRun.find(sync_run_id)
    result = Sync::Up.new.run!
    status = result[:failed].any? ? :failed : :completed

    run.finish!(status: status, summary: result)
  # GuardError aquí solo cae por una carrera (un borrador creado entre el
  # pre-chequeo del controlador y el arranque del job): se reporta legible en
  # el panel en vez de reventar. El camino normal lo ataja el controlador.
  rescue Sync::Up::GuardError, Sync::ApiClient::Error => e
    run&.finish!(status: :failed, message: e.message)
  rescue StandardError => e
    # El detalle técnico (clase, rutas internas, IPs de la red on-prem) va al
    # log; en el panel, guía accionable — mismo criterio que el resto del panel.
    Rails.logger.error(e.full_message)
    run&.finish!(status: :failed, message: "No se pudieron transmitir los pedidos. Revisa que el servidor esté disponible e inténtalo de nuevo.")
    raise
  end
end
