module Sync
  # Cierra la rueda activa en la laptop para poder cargar otra: elimina los
  # pedidos ya transmitidos (viven en el ERP), borra el historial de corridas de
  # sync (pertenece a la rueda que se cierra; el panel arranca limpio),
  # desactiva la rueda y limpia la selección — así el sync-down de la siguiente
  # rueda pasa su guarda.
  #
  # Solo transmitidos y no `Order.destroy_all`: la guarda ya exige que no haya
  # otra cosa, y acotar el borrado es lo que hace imposible perder una venta si
  # algo se finaliza en la ventana entre la guarda y el borrado.
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
      # La verificación y el borrado van bajo el MISMO lock que usa el alta de
      # corridas: si no, entre el `exists?` y el `delete_all` puede colarse una
      # corrida nueva y le borraríamos su registro al job recién arrancado
      # (queda huérfano y el panel gira "en progreso" para siempre).
      SyncRun.exclusively do
        if SyncRun.running.exists?
          raise SyncInProgressError,
                "Se está obteniendo información o transmitiendo pedidos. " \
                "Espera a que termine para cerrar la rueda."
        end

        # La guarda va DENTRO del lock. Fuera quedaba una ventana que incluía la
        # espera del lock —segundos si otra operación lo tenía— entre contar los
        # pedidos y borrarlos.
        Guards.no_local_orders!(PendingOrdersError, "al cerrar la rueda")

        # Solo se borran los transmitidos, y se vuelve a comprobar después. La
        # guarda de arriba y el borrado son dos sentencias distintas: entre ellas
        # otra conexión todavía puede finalizar un pedido (`capture!` no toma
        # este lock), y con `Order.destroy_all` esa venta se perdía en silencio.
        # Así, si algo se coló, la segunda guarda deshace la transacción entera
        # y no se pierde nada — el operador reintenta.
        removed = Order.transmitted.count
        # Ver Order.purge_transmitted!: con `destroy_all`, el candado de
        # promoción dejaba pedidos vivos y "Cerrar rueda" reportaba éxito.
        Order.purge_transmitted!
        Guards.no_local_orders!(PendingOrdersError, "al cerrar la rueda")

        SyncRun.delete_all
        BusinessRound.update_all(active: false)
        Setting.instance.update!(selected_round_erp_id: nil, selected_round_name: nil)
        removed
      end
    end
  end
end
