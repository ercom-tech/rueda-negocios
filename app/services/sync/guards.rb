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
    def no_draft_orders!(error_class)
      drafts = draft_count
      return if drafts.zero?

      raise error_class,
            "Hay #{pedidos(drafts)} en borrador y no se #{drafts == 1 ? 'transmitiría' : 'transmitirían'}. " \
            "Pide que #{lo(drafts)} terminen o #{lo(drafts)} descarten, y vuelve a intentar."
    end

    # Guarda de las operaciones que BORRAN los pedidos de la laptop: obtener la
    # información (su replace reemplaza todo lo local) y cerrar la rueda. Los
    # borradores y los finalizados sin transmitir se perderían; los ya
    # transmitidos no, porque viven en el ERP.
    #
    # `accion` completa la frase ("al obtener la información", "al cerrar la
    # rueda") — es lo único que cambia entre las dos.
    #
    # Avisa de ambos casos de una vez: el orden de solución está forzado (con
    # borradores tampoco se puede transmitir), así que el operador necesita ver
    # el camino completo desde el primer intento y no descubrirlo de mensaje en
    # mensaje.
    def no_local_orders!(error_class, accion)
      drafts  = draft_count
      pending = untransmitted_count
      return if drafts.zero? && pending.zero?

      raise error_class, local_orders_message(drafts, pending, accion)
    end

    def local_orders_message(drafts, pending, accion)
      if drafts.positive? && pending.positive?
        "Hay #{pedidos(drafts)} en borrador y #{pending} sin transmitir; se perderían #{accion}. " \
        "Pide que terminen o descarten los borradores, transmite los demás, y vuelve a intentar."
      elsif drafts.positive?
        "Hay #{pedidos(drafts)} en borrador y se #{perderia(drafts)} #{accion}. " \
        "Pide que #{lo(drafts)} terminen o #{lo(drafts)} descarten, y vuelve a intentar."
      else
        "Hay #{pedidos(pending)} sin transmitir y se #{perderia(pending)} #{accion}. " \
        "#{transmitelo(pending)} y vuelve a intentar."
      end
    end

    def pedidos(count)
      count == 1 ? "1 pedido" : "#{count} pedidos"
    end

    def lo(count)
      count == 1 ? "lo" : "los"
    end

    def perderia(count)
      count == 1 ? "perdería" : "perderían"
    end

    def transmitelo(count)
      count == 1 ? "Transmítelo" : "Transmítelos"
    end
  end
end
