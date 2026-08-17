class SyncUpJob < ApplicationJob
  queue_as :default

  # Transmite los pedidos capturados al ERP. Reporta el resultado en el SyncRun.
  # Si algún pedido falla, el run queda `failed` (transmisión parcial) con el
  # detalle en el resumen para reintentar.
  def perform(sync_run_id)
    run = SyncRun.find(sync_run_id)
    # El barrido pudo cerrarla entre el encolado y este arranque (p. ej. el
    # web se reinició en medio): no correr sobre una corrida ya cerrada.
    return unless run.running?

    # El dueño real es quien ejecuta: con un worker aparte (Solid Queue en
    # production.rb), el pid del web moría con un restart de puma y el
    # barrido marcaba fallida una corrida viva (6ª auditoría).
    run.update!(pid: Process.pid)
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
  ensure
    # Espejo del rake: una excepción fuera de StandardError en el hilo del
    # job (NoMemoryError, SystemStackError) dejaba la corrida running con
    # dueño vivo — el barrido no la tocaba hasta reiniciar (6ª auditoría).
    run.finish_interrupted! if run&.running?
  end
end
