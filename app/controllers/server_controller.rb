class ServerController < ApplicationController
  # Panel de operación del sync, exclusivo del rol server. Las acciones pesadas
  # (sync-down / sync-up) se ejecutan en background; el menú refleja su estado.
  layout "auth"

  before_action :require_server

  # Elegir la rueda a trabajar: lista las disponibles en el ERP.
  def rounds
    @selected = Setting.instance.selected_round_erp_id
    @rounds   = Sync::ApiClient.new.list_rounds
  rescue Sync::ApiClient::Error => e
    # El detalle técnico (URL interna, "Connection refused") va al log; al
    # operador se le da una guía accionable.
    Rails.logger.warn("rounds: #{e.message}")
    @rounds = []
    flash.now[:alert] = "No se pudo obtener la lista de ruedas. " \
                        "Verifica que el servidor rueda-api esté disponible e inténtalo de nuevo."
  end

  # Guardar la rueda seleccionada.
  def select_round
    Setting.instance.update!(
      selected_round_erp_id: params[:erp_round_id].presence,
      selected_round_name:   params[:name].presence
    )
    redirect_to root_path, notice: "Rueda seleccionada. Ya puedes obtener su información."
  end

  # Obtener la información del servidor (descarga el dataset = sync-down).
  def sync_down
    if Setting.instance.selected_round_erp_id.blank?
      return redirect_to server_rounds_path, alert: "Primero elige la rueda a trabajar."
    end
    if SyncRun.latest("down")&.running?
      return redirect_to root_path, alert: "Ya hay una descarga en curso."
    end

    run = SyncRun.create!(kind: "down", started_at: Time.current)
    SyncDownJob.perform_later(run.id)
    redirect_to root_path, notice: "Descarga iniciada. El menú se actualizará al terminar."
  rescue ActiveRecord::RecordNotUnique
    # Carrera (dos POST casi simultáneos): el índice único parcial de sync_runs
    # deja pasar solo un run `running` por tipo.
    redirect_to root_path, alert: "Ya hay una descarga en curso."
  end

  # Transmitir los pedidos capturados al ERP (sync-up).
  def sync_up
    if SyncRun.latest("up")&.running?
      return redirect_to root_path, alert: "Ya hay una transmisión en curso."
    end

    run = SyncRun.create!(kind: "up", started_at: Time.current)
    SyncUpJob.perform_later(run.id)
    redirect_to root_path, notice: "Transmisión iniciada. El menú se actualizará al terminar."
  rescue ActiveRecord::RecordNotUnique
    redirect_to root_path, alert: "Ya hay una transmisión en curso."
  end

  # Cerrar la rueda activa: purga los pedidos locales (los transmitidos ya
  # viven en el ERP) para poder cargar otra rueda con el sync-down.
  def close_round
    removed = Sync::CloseRound.run!
    redirect_to root_path,
                notice: "Rueda cerrada (#{removed} pedido(s) locales eliminados). " \
                        "Elige la siguiente rueda y obtén su información."
  rescue Sync::CloseRound::PendingOrdersError => e
    redirect_to root_path, alert: "#{e.message} Transmite antes de cerrar la rueda."
  end
end
