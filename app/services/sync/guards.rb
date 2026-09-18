module Sync
  # Guardas compartidas por el sync-down y el sync-up, con los mensajes que lee
  # el operador. Viven juntas para que la regla y su redacción no se
  # desincronicen entre los dos servicios.
  #
  # Los textos van en lenguaje de operación, sin vocabulario técnico: quien los
  # lee está en el evento resolviendo un problema, no depurando el sistema. Y
  # concuerdan en número — un "se perderían 1 pedido" delata descuido justo
  # cuando el operador necesita confiar en lo que lee.
  module Guards
    module_function

    # Dónde encuentra el equipo-servidor los borradores para resolverlos. Con
    # los nombres que ve en pantalla, no con los de las rutas.
    DRAFTS_PATH = "Reportes de venta → Pedidos capturados → Borrador".freeze

    # Pedidos que todavía viven solo en la laptop.
    def draft_count
      Order.draft.count
    end

    def untransmitted_count
      Order.captured.where(erp_folio: nil).count
    end

    # Guarda del sync-up: un pedido en borrador sigue en captura y no se
    # transmite (solo se envían los finalizados), así que el operador se
    # quedaría creyendo que ya todo llegó al ERP.
    #
    # La salida la tiene el propio operador (11ª auditoría): el equipo-servidor
    # puede guardar o descartar un borrador ajeno, y el aviso tiene que decirlo
    # y decir DÓNDE. Antes solo mandaba a pedírselo al capturista, que en el
    # caso que importa —el que dejó el borrador abierto— ya no está. Aquí
    # guardarlo basta, porque el reintento lo transmite con los demás.
    def no_draft_orders!(error_class)
      drafts = draft_count
      return if drafts.zero?

      raise error_class,
            "Hay #{orders_label(drafts)} en borrador y no se #{drafts == 1 ? 'transmitiría' : 'transmitirían'}. " \
            "#{save_or_discard(drafts)} desde #{DRAFTS_PATH} (o pide que #{them(drafts)} terminen), " \
            "y vuelve a intentar."
    end

    # Guarda de las operaciones que BORRAN los pedidos de la laptop: obtener la
    # información (su replace reemplaza todo lo local) y cerrar la rueda. Los
    # borradores y los finalizados sin transmitir se perderían; los ya
    # transmitidos no, porque viven en el ERP.
    #
    # `action` completa la frase ("al obtener la información", "al cerrar la
    # rueda") — es lo único que cambia entre las dos.
    #
    # Avisa de ambos casos de una vez: el orden de solución está forzado (con
    # borradores tampoco se puede transmitir), así que el operador necesita ver
    # el camino completo desde el primer intento y no descubrirlo de mensaje en
    # mensaje.
    def no_local_orders!(error_class, action)
      drafts  = draft_count
      pending = untransmitted_count
      return if drafts.zero? && pending.zero?

      raise error_class, local_orders_message(drafts, pending, action)
    end

    def local_orders_message(drafts, pending, action)
      # Aquí GUARDAR no basta: un borrador guardado queda capturado sin
      # transmitir, y eso también bloquea. Por eso el camino dice "guárdalo y
      # transmítelo, o descártalo", completo desde el primer aviso.
      if drafts.positive? && pending.positive?
        "Hay #{orders_label(drafts)} en borrador y #{pending} sin transmitir; se perderían #{action}. " \
        "Guarda o descarta #{drafts == 1 ? 'el borrador' : 'los borradores'} desde #{DRAFTS_PATH}, " \
        "transmite los demás, y vuelve a intentar."
      elsif drafts.positive?
        "Hay #{orders_label(drafts)} en borrador y se #{would_be_lost(drafts)} #{action}. " \
        "Desde #{DRAFTS_PATH}, #{save_and_transmit_or_discard(drafts)}; y vuelve a intentar."
      else
        # La alternativa de descartar no es adorno: un pedido atorado en la
        # colisión del 422 jamás va a transmitirse — sin ella, esta guarda
        # ordenaba lo imposible y bloqueaba cerrar la rueda (6ª auditoría).
        "Hay #{orders_label(pending)} sin transmitir y se #{would_be_lost(pending)} #{action}. " \
        "#{transmit_them(pending)} (o pide a su capturista que #{them(pending)} descarte) y vuelve a intentar."
      end
    end

    def orders_label(count)
      count == 1 ? "1 pedido" : "#{count} pedidos"
    end

    def them(count)
      count == 1 ? "lo" : "los"
    end

    def would_be_lost(count)
      count == 1 ? "perdería" : "perderían"
    end

    def transmit_them(count)
      count == 1 ? "Transmítelo" : "Transmítelos"
    end

    def save_or_discard(count)
      count == 1 ? "Guárdalo o descártalo" : "Guárdalos o descártalos"
    end

    def save_and_transmit_or_discard(count)
      count == 1 ? "guárdalo y transmítelo, o descártalo" : "guárdalos y transmítelos, o descártalos"
    end
  end
end
