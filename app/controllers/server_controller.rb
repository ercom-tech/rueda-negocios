class ServerController < ApplicationController
  # Panel de operación del sync, exclusivo del rol server. Las acciones pesadas
  # (sync-down / sync-up) se ejecutan en background; el menú refleja su estado.
  layout "auth"

  before_action :require_server

  # Elegir la rueda a trabajar: lista las disponibles en el ERP. Bloqueado
  # mientras haya una rueda en curso: el cambio de rueda pasa SIEMPRE por
  # "Cerrar rueda" (y sus guardas: capturados sin transmitir, sync corriendo).
  # Se protege también el PATCH, no solo la card del menú, para que un URL
  # directo o el back del navegador no se brinquen la regla.
  def rounds
    return redirect_to root_path, alert: round_in_progress_alert if round_in_progress?

    @rounds = Sync::ApiClient.new.list_rounds
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
    return redirect_to root_path, alert: round_in_progress_alert if round_in_progress?

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
    # Cualquier corrida viva bloquea lanzar otra, del tipo que sea: una
    # descarga a media transmisión (o viceversa) pisaría los datos del job
    # en vuelo. Mismo criterio que la guarda de "Cerrar rueda".
    if SyncRun.running.exists?
      return redirect_to root_path, alert: "Hay una corrida de sync en curso. Espera a que termine."
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
    unless round_in_progress?
      return redirect_to root_path, alert: "No hay rueda en curso; no hay pedidos que transmitir."
    end
    if SyncRun.running.exists?
      return redirect_to root_path, alert: "Hay una corrida de sync en curso. Espera a que termine."
    end
    # Mismo patrón que "Cerrar rueda": la card se ve normal, el modal aparece
    # y la condición no cumplida se avisa al confirmar. Va ANTES de crear el
    # SyncRun para no dejar una corrida fallida por una condición previa.
    Sync::Up.guard!

    run = SyncRun.create!(kind: "up", started_at: Time.current)
    SyncUpJob.perform_later(run.id)
    redirect_to root_path, notice: "Transmisión iniciada. El menú se actualizará al terminar."
  rescue Sync::Up::GuardError => e
    redirect_to root_path, alert: "#{e.message} Deben finalizarse o descartarse antes de transmitir."
  rescue ActiveRecord::RecordNotUnique
    redirect_to root_path, alert: "Ya hay una transmisión en curso."
  end

  # Cerrar la rueda activa: purga los pedidos locales (los transmitidos ya
  # viven en el ERP) para poder cargar otra rueda con el sync-down.
  def close_round
    unless round_in_progress?
      return redirect_to root_path, alert: "No hay rueda que cerrar."
    end

    removed = Sync::CloseRound.run!
    redirect_to root_path,
                notice: "Rueda cerrada (#{removed} pedido(s) locales eliminados). " \
                        "Elige la siguiente rueda y obtén su información."
  rescue Sync::CloseRound::PendingOrdersError => e
    redirect_to root_path, alert: "#{e.message} Transmite antes de cerrar la rueda."
  rescue Sync::CloseRound::SyncInProgressError => e
    redirect_to root_path, alert: "#{e.message} Espera a que termine para cerrar la rueda."
  end

  private

  def round_in_progress?
    Setting.instance.selected_round_erp_id.present?
  end

  def round_in_progress_alert
    setting = Setting.instance
    name    = setting.selected_round_name.presence || "##{setting.selected_round_erp_id}"
    "Ya hay una rueda en curso (#{name}). Ciérrala antes de elegir otra."
  end
end
