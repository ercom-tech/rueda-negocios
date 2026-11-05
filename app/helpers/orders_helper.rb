module OrdersHelper
  # "la partida" / "las 3 partidas": la concordancia de la conversión, en un
  # solo lugar (19ª auditoría: estaba escrita a mano en dos modales, con dos
  # redacciones distintas y el singular de uno sin probar).
  def estimate_items_phrase(count)
    count == 1 ? "la partida" : "las #{count} partidas"
  end

  # El mensaje de los DOS modales de "Convertir en pedido": el de la
  # cotización con cliente (`client` es el cliente) y el del paso 1 de la
  # genérica (`client` nil: todavía no se sabe cuál se elegirá).
  def conversion_confirm_message(estimate, client = nil)
    whose = client ? "de (#{client.erp_client_key}) #{client.commercial_name.presence || client.name}" : "del cliente elegido"
    "Se creará el pedido #{whose} con #{estimate_items_phrase(estimate.order_items.size)} de la cotización " \
      "#{estimate.folio}, ya guardado: se enviará al ERP en la siguiente transmisión. " \
      "La cotización se eliminará. ¿Continuar?"
  end
end
