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
    # La vista distingue con esto el éxito-sin-ruedas (pide registrarlas en el
    # ERP) del fallo de conexión: sin la bandera, el estado vacío decía "(o no
    # se pudo contactar al servidor)" también en el caso bueno y mandaba a
    # revisar la red sin necesidad.
    @fetch_failed = true
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
    # Mismo patrón que "Cerrar rueda" y "Transmitir pedidos": la condición no
    # cumplida se avisa al confirmar. Va ANTES de crear el SyncRun para no
    # dejar una corrida fallida por algo que nunca llegó a intentarse.
    Sync::Down.guard!

    # Cualquier corrida viva bloquea lanzar otra, del tipo que sea: una
    # descarga a media transmisión (o viceversa) pisaría los datos del job en
    # vuelo. `SyncRun.start` verifica y crea bajo un mismo lock — hacerlo en
    # dos pasos deja pasar un down y un up simultáneos.
    run = SyncRun.start("down")
    return redirect_to root_path, alert: sync_busy_alert if run.nil?

    SyncDownJob.perform_later(run.id)
    redirect_to root_path, notice: "Obteniendo la información. El menú se actualizará al terminar."
  rescue Sync::Down::GuardError => e
    redirect_to root_path, alert: e.message
  rescue ActiveRecord::RecordNotUnique
    # Carrera (dos POST casi simultáneos): el índice único parcial de sync_runs
    # deja pasar solo un run `running` por tipo.
    redirect_to root_path, alert: "Ya se está obteniendo la información."
  end

  # Transmitir los pedidos capturados al ERP (sync-up).
  def sync_up
    unless round_in_progress?
      return redirect_to root_path, alert: "No hay rueda en curso; no hay pedidos que transmitir."
    end
    # Mismo patrón que "Cerrar rueda": la card se ve normal, el modal aparece
    # y la condición no cumplida se avisa al confirmar. Va ANTES de crear el
    # SyncRun para no dejar una corrida fallida por una condición previa.
    Sync::Up.guard!

    run = SyncRun.start("up")
    return redirect_to root_path, alert: sync_busy_alert if run.nil?

    SyncUpJob.perform_later(run.id)
    redirect_to root_path, notice: "Transmisión iniciada. El menú se actualizará al terminar."
  rescue Sync::Up::GuardError => e
    redirect_to root_path, alert: e.message
  rescue ActiveRecord::RecordNotUnique
    redirect_to root_path, alert: "Ya se están transmitiendo los pedidos."
  end

  # Cerrar la rueda activa: purga los pedidos locales (los transmitidos ya
  # viven en el ERP) para poder cargar otra rueda con el sync-down.
  def close_round
    unless round_in_progress?
      return redirect_to root_path, alert: "No hay rueda que cerrar."
    end

    removed = Sync::CloseRound.run!
    redirect_to root_path,
                notice: "Rueda cerrada. Se eliminaron #{helpers.pluralize(removed, 'pedido')} de esta laptop. " \
                        "Elige la siguiente rueda y obtén su información."
  rescue Sync::CloseRound::PendingOrdersError, Sync::CloseRound::SyncInProgressError => e
    redirect_to root_path, alert: e.message
  end

  private

  def round_in_progress?
    Setting.instance.selected_round_erp_id.present?
  end

  def sync_busy_alert
    "Se está obteniendo información o transmitiendo pedidos. Espera a que termine."
  end

  def round_in_progress_alert
    setting = Setting.instance
    name    = setting.selected_round_name.presence || "##{setting.selected_round_erp_id}"
    "Ya hay una rueda en curso (#{name}). Ciérrala antes de elegir otra."
  end
end
