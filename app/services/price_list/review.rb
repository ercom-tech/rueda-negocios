module PriceList
  # Compara los renglones del archivo (`Reader`) contra el catálogo de la rueda
  # activa y dice qué pasaría al aplicarlo, SIN escribir nada. `apply!` es lo
  # único que escribe.
  #
  # Se compara contra el precio con que HOY se captura (`Product#capture_price`),
  # no contra el del ERP: es lo que el capturista ve, y lo que el archivo va a
  # cambiar. Un precio igual al de hoy no se escribe.
  #
  # Los archivos se SUMAN (decisión del usuario 2026-10-08): aplicar uno solo
  # toca sus códigos, y en un código ya cargado gana el último.
  class Review
    # Arriba del umbral se señala, pero se aplica igual: puede ser un error de
    # captura en el archivo o un cambio real, y solo el operador lo sabe. El
    # umbral lo elige el operador en la pantalla (2026-10-08); este es el de
    # omisión. Solo decide qué se SEÑALA, nunca qué se aplica.
    LARGE_VARIATION = BigDecimal("0.5")

    Change = Data.define(:line, :code, :description, :current_price, :new_price) do
      # nil cuando el producto no tenía precio: no hay contra qué comparar.
      def variation = current_price&.positive? ? new_price / current_price - 1 : nil

      # Un precio que aparece de la nada (el producto estaba en $0 o sin
      # precio) se señala SIEMPRE: no hay variación con que medirlo, y era
      # justo donde un precio mal leído pasaba sin ruido (13ª auditoría).
      def large_variation?(threshold = LARGE_VARIATION) = variation.nil? || variation.abs > threshold
    end
    # Un código que el archivo trae con precios distintos: no se adivina cuál.
    Conflict = Data.define(:code, :lines, :prices)

    attr_reader :round, :changes, :unchanged, :not_in_round, :conflicts, :problems, :threshold

    # `threshold`: fracción (0.2 = 20%) a partir de la cual una variación se
    # señala.
    def initialize(reader, threshold: LARGE_VARIATION)
      @threshold = threshold
      @round = BusinessRound.active.first
      raise Error, "No hay una rueda cargada. Obtén la información de la rueda antes de cambiar precios." unless @round

      @problems     = reader.problems.dup
      @changes      = []
      @unchanged    = []
      @not_in_round = []
      @conflicts    = []
      compare(reader.rows)
    end

    # Cuántos suben y cuántos bajan, para el segundo renglón de las tarjetas.
    # Un producto que no tenía precio "sube": pasa de nada a algo.
    def directions(group)
      up = group.count { |c| c.new_price > (c.current_price || 0) }
      { up: up, down: group.size - up }
    end

    # Lo que no se aplica, contado por tipo de motivo y del más frecuente al
    # menos; a igual cuenta, en el orden en que aparecen.
    def rejected_kinds = rejected.map(&:kind).tally.sort_by.with_index { |(_, n), i| [ -n, i ] }

    def large?(change) = change.large_variation?(threshold)
    def large_variations = changes.select { |c| large?(c) }

    # Todo lo del archivo que NO se va a aplicar, con su motivo y en el orden
    # del archivo: lo que el operador tiene que ir a corregir.
    def rejected
      (problems +
       conflicts.map do |c|
         Reader::Problem.new(line: c.lines.first, code_text: format("%06d", c.code),
                             reason: "Viene repetido con precios distintos (líneas #{SpanishText.list(c.lines.map(&:to_s))}).",
                             kind: :conflict)
       end +
       not_in_round.map do |r|
         Reader::Problem.new(line: r.line, code_text: format("%06d", r.code), reason: "No está en el catálogo de esta rueda.",
                             kind: :not_in_round)
       end).sort_by(&:line)
    end

    # Borradores con alguna partida de estos productos a un precio distinto del
    # nuevo. No se tocan —el precio de una partida es el que se le ofreció al
    # cliente—, pero el operador tiene que saber que existen.
    #
    # Con QUIÉN y de qué cliente: el servidor no puede editar borradores ajenos,
    # así que el aviso solo sirve si dice a qué capturista avisarle (13ª
    # auditoría). Los regalos no cuentan: van al 100% de descuento y su precio
    # no mueve el total. `locked` son las partidas con promoción aplicada, que
    # no se pueden quitar sin quitar antes la promoción.
    StaleDraft = Data.define(:capturista, :client, :items, :locked)

    def stale_drafts
      new_price = changes.to_h { |c| [ c.code, c.new_price ] }
      return [] if new_price.empty?

      stale = OrderItem.joins(:order, :product)
                       .where(orders: { status: "draft" }, products: { erp_product_id: new_price.keys }, gift: false)
                       .pluck("orders.id", "products.erp_product_id", :unit_price, :promotion_id)
                       .select { |_, code, price, _| price != new_price[code] }
                       .group_by(&:first)
      orders = Order.where(id: stale.keys).includes(:user, :client).order(:id)
      orders.map do |order|
        items = stale[order.id]
        StaleDraft.new(capturista: order.user.full_name.presence || order.user.username, client: order.client.name,
                       items: items.size, locked: items.count { |*, promotion_id| promotion_id })
      end
    end

    # Escribe los cambios. Vuelve a mirar las condiciones que pudieron cambiar
    # desde la revisión: que la rueda siga siendo la misma y que no esté
    # corriendo un sync (que recrea el catálogo con el que se comparó).
    #
    # Bajo el MISMO candado que las corridas y "Cerrar rueda": comprobar y
    # escribir eran dos sentencias, y un cierre colado entre ellas dejaba
    # precios con la rueda ya cerrada, que reaparecían si se volvía a obtener
    # (13ª auditoría).
    def apply!(filename:, loaded_by:)
      SyncRun.exclusively do
        if SyncRun.running.exists?
          raise Error, "Se está obteniendo información o transmitiendo pedidos. Espera a que termine para cambiar precios."
        end
        unless BusinessRound.active.where(erp_round_id: round.erp_round_id).exists?
          raise Error, "La rueda cambió desde que se revisó el archivo. Vuelve a subirlo."
        end
        write_changes!(filename, loaded_by)
      end
    end

    private

    def write_changes!(filename, loaded_by)
      return 0 if changes.empty?

      # Fechas explícitas con el reloj de la app: así `updated_at` dice cuándo
      # se cargó cada precio aunque la fila ya existiera, y las pruebas pueden
      # moverlo con `travel` (el CURRENT_TIMESTAMP de Postgres no se mueve).
      now = Time.current
      PriceOverride.upsert_all(
        changes.map do |c|
          { erp_round_id: round.erp_round_id, erp_product_id: c.code, unit_price: c.new_price,
            source_filename: filename.to_s.first(255), loaded_by: loaded_by, created_at: now, updated_at: now }
        end,
        unique_by: %i[erp_round_id erp_product_id],
        update_only: %i[unit_price source_filename loaded_by updated_at],
        record_timestamps: false
      )
      changes.size
    end

    def compare(rows)
      by_code = rows.group_by(&:code)
      products = Product.where(erp_product_id: by_code.keys).includes(:price, :price_override)
                        .index_by(&:erp_product_id)

      by_code.each do |code, same_code|
        prices = same_code.map(&:price).uniq
        next @conflicts << Conflict.new(code:, lines: same_code.map(&:line), prices:) if prices.size > 1

        row = same_code.first
        product = products[code]
        if code == Product::GENERIC_ERP_ID
          @problems << Reader::Problem.new(line: row.line, code_text: format("%06d", code),
                                           reason: "El 999999 no lleva precio de lista: se captura a mano en cada partida.",
                                           kind: :generic)
        elsif product.nil?
          @not_in_round << row
        else
          current = product.capture_price
          change = Change.new(line: row.line, code:, description: product.description,
                              current_price: current, new_price: row.price)
          current == row.price ? @unchanged << change : @changes << change
        end
      end
      @problems.sort_by!(&:line)
    end
  end
end
