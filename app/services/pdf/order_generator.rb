require "prawn"
require "prawn/table"

module Pdf
  # Genera el PDF del pedido con Prawn replicando el formato impreso del ERP
  # de FECEGO (ver docs/design-reference / muestras PedidoKE*.pdf del b2b):
  # logo + datos de la empresa, "PEDIDO" + clave/fecha, bloque cliente +
  # atributos, tabla con bordes (Código/Descripción/Unidad/Cantidad/Precio/
  # Monto/%Dto./Subtotal/%IVA/Total), importe en letra y totales. Offline.
  class OrderGenerator
    include ActionView::Helpers::NumberHelper

    COMPANY_NAME    = "FERRETERA CENTRAL DEL GOLFO, S.A. DE C.V.".freeze
    COMPANY_RFC     = "FCG820510KJ3".freeze
    COMPANY_ADDRESS = "DÍAZ MIRON NO.5".freeze
    COMPANY_PHONE   = "232 324 9060".freeze
    LOGO_PATH       = Rails.root.join("app/assets/images/fecego_logo_dark.png").freeze

    ITEM_COLUMN_WIDTHS = [ 55, 197, 46, 58, 75, 70, 48, 70, 44, 57 ].freeze # suma 720 (landscape)

    def initialize(order)
      @order = order
    end

    # Prawn avisa en CADA render que sus fuentes internas tienen soporte
    # limitado de UTF-8. Es cierto y no aplica aquí: el documento va en
    # Helvetica/WinAnsi, que cubre los acentos del español. Silenciarlo evita
    # ensuciar el log del evento con un aviso que no requiere acción.
    Prawn::Fonts::AFM.hide_m17n_warning = true

    def render
      pdf = Prawn::Document.new(
        page_size: "LETTER", page_layout: :landscape, margin: [ 36, 36, 54, 36 ],
        info: { Title: "Pedido #{@order.folio}", Author: COMPANY_NAME, Creator: "rueda-negocios" }
      )
      pdf.font "Helvetica"

      render_header(pdf)
      render_info(pdf)
      render_items_table(pdf)
      render_footer(pdf)
      number_pages(pdf)

      pdf.render
    end

    private

    def render_header(pdf)
      top = pdf.cursor
      pdf.image LOGO_PATH.to_s, at: [ 0, top + 4 ], width: 115

      pdf.text_box "<b>#{COMPANY_NAME}</b>\n#{COMPANY_RFC}\n#{COMPANY_ADDRESS}\n#{COMPANY_PHONE}",
                   at: [ 130, top ], width: 300, size: 9, inline_format: true, leading: 1

      pdf.text_box "PEDIDO", at: [ 455, top - 18 ], width: 110, size: 16, style: :bold, align: :center

      pdf.text_box "<b>CLAVE:  #{esc(@order.folio)}</b>\n<b>Fecha:  #{date_only}</b>",
                   at: [ pdf.bounds.right - 180, top - 14 ], width: 180, size: 10, inline_format: true, align: :right, leading: 2

      pdf.move_cursor_to top - 62
      pdf.stroke_color "000000"
      pdf.stroke_horizontal_rule
      pdf.move_down 8
    end

    def render_info(pdf)
      top = pdf.cursor
      pdf.text_box left_info,  at: [ 0, top ],   width: 470, size: 9, inline_format: true, leading: 2
      pdf.text_box right_info, at: [ 480, top ], width: pdf.bounds.width - 480, size: 9, inline_format: true, leading: 2
      pdf.move_cursor_to top - 70
      pdf.move_down 4
    end

    def render_items_table(pdf)
      header = [ "Código", "Descripción", "Unidad", "Cantidad", "Precio unitario",
                "Monto", "%Dto.", "Subtotal", "%IVA", "Total" ]

      rows = printed_items.map do |i|
        [
          i[:code], i[:description], i[:unit],
          amount(i[:quantity]), money(i[:unit_price]), money(i[:amount]),
          pct(i[:discount_percent]), money(i[:subtotal]), pct(i[:tax_rate]), money(i[:total])
        ]
      end
      rows = [ [ "—" ] + [ "" ] * 9 ] if rows.empty?

      pdf.table([ header ] + rows,
                header: true, column_widths: ITEM_COLUMN_WIDTHS,
                cell_style: { size: 8, padding: [ 3, 4, 3, 4 ], border_color: "999999", borders: [ :top, :bottom, :left, :right ] }) do
        row(0).font_style       = :bold
        row(0).background_color  = "EEEEEE"
        row(0).align             = :center
        columns(1).align         = :left
        columns(0).align         = :left
        columns(2).align         = :center
        [ 3, 4, 5, 6, 7, 8, 9 ].each { |c| columns(c).rows(1..-1).align = :right }
      end
      pdf.move_down 12
    end

    def render_footer(pdf)
      y = pdf.cursor
      # Importe en letra + observaciones (izquierda, en flujo)
      pdf.bounding_box([ 0, y + 4 ], width: 440) do
        pdf.text amount_in_words(printed_total(:total)), size: 9, style: :bold
        if @order.observations.present?
          pdf.move_down 6
          pdf.text "<b>Observaciones:</b>  #{esc(@order.observations)}", size: 9, inline_format: true
        end
      end

      # Totales (derecha) — de los mismos importes que imprime la tabla.
      rows = [
        [ "Subtotal",  number_to_currency(printed_total(:amount)) ],
        [ "Descuento", number_to_currency(printed_total(:discount)) ],
        [ "IVA",       number_to_currency(printed_total(:tax)) ],
        [ "Total",     number_to_currency(printed_total(:total)) ]
      ]
      # Flush a la derecha contra el borde de la tabla de partidas: la columna
      # de montos sin padding derecho, para que los números terminen exactamente
      # en bounds.right (el mismo borde derecho de la tabla).
      pdf.bounding_box([ pdf.bounds.right - 230, y ], width: 230) do
        pdf.table(rows, column_widths: [ 130, 100 ],
                        cell_style: { borders: [], padding: [ 1, 0, 1, 6 ], size: 10 }) do
          column(0).font_style = :bold
          column(1).align      = :right
          column(1).font_style = :bold
          row(-1).borders          = [ :top ]
          row(-1).border_top_width = 0.5
          row(-1).size             = 12
          row(-1).padding          = [ 4, 0, 1, 6 ]
        end
      end
    end

    # El folio y el número de página van al pie de CADA hoja. Un pedido de 45
    # partidas —el tope, o sea un caso común— ocupa dos, y antes la primera
    # decía "Página 1" en duro aunque hubiera dos, y la segunda salía sin logo,
    # sin folio y sin cliente: separada del fajo, no había forma de saber de
    # qué pedido era.
    def number_pages(pdf)
      pdf.number_pages "#{@order.folio} · Página <page> de <total>",
                       at: [ 0, -24 ], width: pdf.bounds.width, align: :right, size: 8,
                       inline_format: false
    end

    # ---- Importes impresos -------------------------------------------------

    # El papel se cuadra sumando columnas, así que TODO lo impreso se deriva de
    # los mismos importes ya redondeados a 2 decimales: la columna Total suma
    # exactamente el Total del pie, y Subtotal − Descuento + IVA da ese mismo
    # Total. Antes cada renglón se redondeaba al imprimirse pero el pie se
    # redondeaba una sola vez, y con 45 partidas la deriva llegaba a ~$0.22: el
    # cliente encontraba centavos de diferencia al revisar su copia.
    #
    # Solo afecta al PDF. Lo que viaja al ERP sigue saliendo de `Order` a
    # precisión completa (ahí `rueda-api` redondea únicamente `total`, que es
    # lo que hace el ERP con sus propios pedidos).
    def printed_items
      @printed_items ||= @order.order_items.map do |item|
        amount   = round2(item.line_total)
        discount = round2(item.discount_amount)
        tax      = round2(item.tax_amount)
        subtotal = amount - discount

        { code: item.code, description: item.description, unit: item.unit,
          quantity: item.quantity, unit_price: item.unit_price,
          discount_percent: item.discount_percent, tax_rate: item.tax_rate,
          amount: amount, discount: discount, tax: tax,
          subtotal: subtotal, total: subtotal + tax }
      end
    end

    def printed_total(key)
      printed_items.sum { |i| i[key] } || 0
    end

    def round2(value)
      (value || 0).round(2)
    end

    # ---- Bloques de texto -------------------------------------------------

    def left_info
      client = @order.client
      lines = [ "<b>Cliente:</b>  (#{esc(client.erp_client_key)})  #{esc(client.commercial_name.presence || client.name)}" ]
      if @order.invoice?
        t = @order.client_tax_profile
        lines << "<b>POR FACTURAR</b>   RFC: #{esc(t&.rfc)}   Razón Social: #{esc(t&.business_name)}"
      else
        lines << "<b>REMISIÓN:</b>  #{esc(@order.client_receipt_profile&.name)}"
      end
      lines << "<b>Sucursal:</b>  #{esc(@order.client_branch&.name)}"
      lines << "<b>Dirección:</b>  #{esc(@order.client_branch&.address)}" if @order.client_branch&.address.present?
      lines << "<b>Uso CFDI:</b>  #{esc(@order.cfdi_use.code)} #{esc(@order.cfdi_use.description)}" if @order.invoice? && @order.cfdi_use
      lines.join("\n")
    end

    def right_info
      vendor     = @order.client.salesperson
      capturista = @order.user.full_name.presence || @order.user.username
      [
        "<b>#{esc(@order.business_round.name)}</b>",
        "Capturado: #{stamp(@order.created_at)} — #{esc(capturista)}",
        ("Transmitido: #{stamp(@order.transmitted_at)}" if @order.transmitted? && @order.transmitted_at),
        ("Vendedor: #{esc([ vendor.erp_salesperson_id, vendor.name ].compact.join(' '))}" if vendor),
        "Estatus: #{@order.status_label.upcase}",
        "Renglones: #{@order.order_items.size}"
      ].compact.join("\n")
    end

    # ---- Helpers ----------------------------------------------------------

    # Los bloques del PDF van con `inline_format: true`, que hace que Prawn
    # parsee el contenido como su mini-lenguaje de etiquetas. Sin escapar, un
    # "ENTREGAR ANTES DE <5 DÍAS>" en observaciones se imprime como "ENTREGAR
    # ANTES DE 5 DÍAS>": la instrucción cambia de sentido en el papel que se le
    # entrega al cliente, y nada avisa. Aplica igual a los datos que vienen del
    # ERP (razón social, dirección), que nadie controla desde aquí.
    def esc(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # `.localtime`: `created_at` se guarda en UTC y `Time.zone` de la app
    # también lo es, así que sin esto un pedido capturado a las 19:30 salía en
    # el papel del cliente como del DÍA SIGUIENTE a la 1:30 — en desacuerdo con
    # el reporte en pantalla y con la fecha que se le manda al ERP, que sí van
    # en hora local. Era el único lugar del proyecto que formateaba sin ella.
    def stamp(time)
      time.localtime.strftime("%d/%m/%Y %H:%M")
    end

    def date_only
      @order.created_at.localtime.strftime("%d/%m/%Y")
    end

    def amount(value)
      number_with_precision(value || 0, precision: 2, delimiter: ",")
    end

    # Importes monetarios de la tabla, con $ como los totales.
    def money(value)
      number_to_currency(value || 0)
    end

    def pct(value)
      number_to_percentage(value || 0, precision: 2)
    end

    def amount_in_words(total)
      # Cuantizar a 2 decimales ANTES de partir entero/centavos: el total del
      # pedido viene a precisión completa y, sin redondear, 100.999 daría
      # "CIEN PESOS 100/100" en vez de "CIENTO UN PESOS 00/100".
      total    = (total || 0).round(2)
      entero   = total.to_i
      centavos = ((total - entero) * 100).round
      # Apócope: "uno" → "un" antes de sustantivo ("ciento un pesos",
      # "veintiun mil") — cubre también "veintiuno" por terminar en "uno".
      palabras = integer_to_words(entero).gsub(/uno(?= mil| millones|\z)/, "un")
      # Concordancia: un total de $1.xx es "UN PESO", no "UN PESOS".
      "#{palabras} #{entero == 1 ? 'peso' : 'pesos'} #{format('%02d', centavos)}/100 M.N.".upcase
    end

    def integer_to_words(n)
      return "cero" if n.zero?

      millones = n / 1_000_000
      miles    = (n % 1_000_000) / 1_000
      cientos  = n % 1_000
      out = []
      # Recursivo en millones: cubre también miles de millones (>10^9).
      out << (millones == 1 ? "un millon" : "#{integer_to_words(millones)} millones") if millones.positive?
      out << (miles == 1 ? "mil" : "#{hundreds_to_words(miles)} mil") if miles.positive?
      out << hundreds_to_words(cientos) if cientos.positive?
      out.join(" ")
    end

    def hundreds_to_words(n)
      return "cien" if n == 100

      centenas = [ "", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos",
                  "seiscientos", "setecientos", "ochocientos", "novecientos" ]
      parts = []
      parts << centenas[n / 100] if n >= 100
      parts << tens_to_words(n % 100) if (n % 100).positive?
      parts.join(" ")
    end

    def tens_to_words(n)
      unidades = [ "", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve",
                  "diez", "once", "doce", "trece", "catorce", "quince", "dieciseis", "diecisiete",
                  "dieciocho", "diecinueve", "veinte", "veintiuno", "veintidos", "veintitres",
                  "veinticuatro", "veinticinco", "veintiseis", "veintisiete", "veintiocho", "veintinueve" ]
      return unidades[n] if n <= 29

      decenas = [ "", "", "", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa" ]
      d = decenas[n / 10]
      u = n % 10
      u.zero? ? d : "#{d} y #{unidades[u]}"
    end
  end
end
