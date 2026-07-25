class SyncDownJob < ApplicationJob
  queue_as :default

  # Descarga el dataset de la rueda seleccionada y puebla el Postgres local
  # (replace). Reporta el avance en el SyncRun asociado.
  def perform(sync_run_id)
    run = SyncRun.find(sync_run_id)
    round_id = Setting.instance.selected_round_erp_id
    raise Sync::ApiClient::Error, "no hay una rueda seleccionada" if round_id.blank?

    data   = Sync::ApiClient.new.fetch_export(round_id)
    result = ActiveRecord::Base.transaction { Sync::Down.new(data).run! }

    run.finish!(status: :completed, summary: result.summary)
  rescue Sync::Down::GuardError, Sync::ApiClient::Error => e
    run&.finish!(status: :failed, message: e.message)
  rescue StandardError => e
    run&.finish!(status: :failed, message: "#{e.class}: #{e.message}")
    raise
  end
end
