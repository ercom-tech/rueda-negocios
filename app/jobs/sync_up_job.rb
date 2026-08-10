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
    run&.finish!(status: :failed, message: "#{e.class}: #{e.message}")
    raise
  end
end
