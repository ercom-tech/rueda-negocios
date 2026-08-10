module Sync
  # Cierra la rueda activa en la laptop para poder cargar otra: elimina los
  # pedidos locales (los transmitidos ya viven en el ERP; los borradores son
  # capturas incompletas), borra el historial de corridas de sync (pertenece a
  # la rueda que se cierra; el panel arranca limpio), desactiva la rueda y
  # limpia la selección — así el sync-down de la siguiente rueda pasa su
  # guarda (`Order.exists?`).
  #
  # Guardas propias: NO cierra si hay pedidos que solo viven en la laptop —
  # borradores (capturas en curso) o finalizados sin transmitir (ventas reales
  # que aún no llegan al ERP) — ni si hay una corrida de sync en curso
  # (borrarle su SyncRun al job vivo lo rompería). La guarda de los pedidos es
  # la MISMA que la de obtener información (`Guards.no_local_orders!`): las dos
  # operaciones borran todo lo local, así que la regla y su redacción son una
  # sola.
  class CloseRound
    # Cubre borradores y finalizados sin transmitir: ambos se perderían.
    class PendingOrdersError < StandardError; end
    class SyncInProgressError < StandardError; end

    def self.run!
      Guards.no_local_orders!(PendingOrdersError, "al cerrar la rueda")
      if SyncRun.running.exists?
        raise SyncInProgressError,
              "Se está obteniendo información o transmitiendo pedidos. " \
              "Espera a que termine para cerrar la rueda."
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
