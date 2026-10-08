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
    # Arriba de esto se señala, pero se aplica igual: puede ser un error de
    # captura en el archivo o un cambio real, y solo el operador lo sabe.
    LARGE_VARIATION = BigDecimal("0.5")

    Change = Data.define(:line, :code, :description, :current_price, :new_price) do
      # nil cuando el producto no tenía precio: no hay contra qué comparar.
      def variation = current_price&.positive? ? new_price / current_price - 1 : nil
      def large_variation? = !variation.nil? && variation.abs > LARGE_VARIATION
    end
    # Un código que el archivo trae con precios distintos: no se adivina cuál.
    Conflict = Data.define(:code, :lines, :prices)

    attr_reader :round, :changes, :unchanged, :not_in_round, :conflicts, :problems

    def initialize(reader)
      @round = BusinessRound.active.first
      raise Error, "No hay una rueda cargada. Obtén la información de la rueda antes de cambiar precios." unless @round

      @problems     = reader.problems.dup
      @changes      = []
      @unchanged    = []
      @not_in_round = []
      @conflicts    = []
      compare(reader.rows)
    end

    def large_variations = changes.select(&:large_variation?)

    # Todo lo del archivo que NO se va a aplicar, con su motivo y en el orden
    # del archivo: lo que el operador tiene que ir a corregir.
    def rejected
      (problems +
       conflicts.map do |c|
         Reader::Problem.new(line: c.lines.first, code_text: format("%06d", c.code),
                             reason: "Viene repetido con precios distintos (líneas #{SpanishText.list(c.lines.map(&:to_s))}).")
       end +
       not_in_round.map do |r|
         Reader::Problem.new(line: r.line, code_text: format("%06d", r.code), reason: "No está en el catálogo de esta rueda.")
       end).sort_by(&:line)
    end

    # Borradores con alguna partida de estos productos a un precio distinto del
    # nuevo. No se tocan —el precio de una partida es el que se le ofreció al
    # cliente—, pero el operador tiene que saber que existen.
    def drafts_with_old_price
      new_price = changes.to_h { |c| [ c.code, c.new_price ] }
      return 0 if new_price.empty?

      OrderItem.joins(:order, :product)
               .where(orders: { status: "draft" }, products: { erp_product_id: new_price.keys })
               .pluck("orders.id", "products.erp_product_id", :unit_price)
               .select { |_, code, price| price != new_price[code] }
               .map(&:first).uniq.size
    end

    # Escribe los cambios. Vuelve a mirar las condiciones que pudieron cambiar
    # desde la revisión: que la rueda siga siendo la misma y que no esté
    # corriendo un sync (que recrea el catálogo con el que se comparó).
    def apply!(filename:, loaded_by:)
      if SyncRun.running.exists?
        raise Error, "Se está obteniendo información o transmitiendo pedidos. Espera a que termine para cambiar precios."
      end
      unless BusinessRound.active.where(erp_round_id: round.erp_round_id).exists?
        raise Error, "La rueda cambió desde que se revisó el archivo. Vuelve a subirlo."
      end
      return 0 if changes.empty?

      # Fechas explícitas: con `update_only`, Rails NO toca `updated_at` en las
      # filas que ya existían, y se perdía cuándo se cambió cada precio.
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

    private

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
                                           reason: "El 999999 no lleva precio de lista: se captura a mano en cada partida.")
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
