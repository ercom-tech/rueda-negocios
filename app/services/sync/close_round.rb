module Sync
  # Cierra la rueda activa en la laptop para poder cargar otra: elimina los
  # pedidos locales (los transmitidos ya viven en el ERP; los borradores son
  # capturas incompletas), desactiva la rueda y limpia la selección — así el
  # sync-down de la siguiente rueda pasa su guarda (`Order.exists?`).
  #
  # Guarda propia: NO cierra si hay pedidos capturados sin transmitir (ventas
  # reales que aún no llegan al ERP y se perderían).
  class CloseRound
    class PendingOrdersError < StandardError; end

    def self.run!
      pending = Order.captured.where(erp_folio: nil).count
      if pending.positive?
        raise PendingOrdersError,
              "Hay #{pending} pedido(s) capturado(s) sin transmitir."
      end

      removed = Order.count
      ActiveRecord::Base.transaction do
        Order.destroy_all
        BusinessRound.update_all(active: false)
        Setting.instance.update!(selected_round_erp_id: nil, selected_round_name: nil)
      end
      removed
    end
  end
end
