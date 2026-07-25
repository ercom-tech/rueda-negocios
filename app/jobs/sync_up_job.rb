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
  rescue Sync::ApiClient::Error => e
    run&.finish!(status: :failed, message: e.message)
  rescue StandardError => e
    run&.finish!(status: :failed, message: "#{e.class}: #{e.message}")
    raise
  end
end
