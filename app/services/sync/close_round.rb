module Sync
  # Cierra la rueda activa en la laptop para poder cargar otra: elimina los
  # pedidos locales (los transmitidos ya viven en el ERP; los borradores son
  # capturas incompletas), borra el historial de corridas de sync (pertenece a
  # la rueda que se cierra; el panel arranca limpio), desactiva la rueda y
  # limpia la selección — así el sync-down de la siguiente rueda pasa su
  # guarda (`Order.exists?`).
  #
  # Guardas propias: NO cierra si hay pedidos capturados sin transmitir
  # (ventas reales que aún no llegan al ERP y se perderían) ni si hay una
  # corrida de sync en curso (borrarle su SyncRun al job vivo lo rompería).
  class CloseRound
    class PendingOrdersError < StandardError; end
    class SyncInProgressError < StandardError; end

    def self.run!
      pending = Order.captured.where(erp_folio: nil).count
      if pending.positive?
        raise PendingOrdersError,
              "Hay #{pending} pedido(s) capturado(s) sin transmitir."
      end
      if SyncRun.running.exists?
        raise SyncInProgressError, "Hay una corrida de sync en curso."
      end

      removed = Order.count
      ActiveRecord::Base.transaction do
        Order.destroy_all
        SyncRun.delete_all
        BusinessRound.update_all(active: false)
        Setting.instance.update!(selected_round_erp_id: nil, selected_round_name: nil)
      end
      removed
    end
  end
end
