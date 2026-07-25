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

    ITEM_COLUMN_WIDTHS = [55, 210, 46, 58, 62, 70, 48, 70, 44, 57].freeze # suma 720 (landscape)

    def initialize(order)
      @order = order
    end

    def render
      pdf = Prawn::Document.new(
        page_size: "LETTER", page_layout: :landscape, margin: [36, 36, 54, 36],
        info: { Title: "Pedido #{@order.folio}", Author: COMPANY_NAME, Creator: "rueda-negocios" }
      )
      pdf.font "Helvetica"

      render_header(pdf)
      render_info(pdf)
      render_items_table(pdf)
      render_footer(pdf)

      pdf.render
    end

    private

    def render_header(pdf)
      top = pdf.cursor
      pdf.image LOGO_PATH.to_s, at: [0, top + 4], width: 115

      pdf.text_box "<b>#{COMPANY_NAME}</b>\n#{COMPANY_RFC}\n#{COMPANY_ADDRESS}\n#{COMPANY_PHONE}",
                   at: [130, top], width: 300, size: 9, inline_format: true, leading: 1

      pdf.text_box "PEDIDO", at: [455, top - 18], width: 110, size: 16, style: :bold, align: :center

      pdf.text_box "#{@order.folio} - Página 1\n\n<b>CLAVE:  #{@order.folio}</b>\n<b>Fecha:  #{date_only}</b>",
                   at: [pdf.bounds.right - 180, top], width: 180, size: 10, inline_format: true, align: :right, leading: 2

      pdf.move_cursor_to top - 62
      pdf.stroke_color "000000"
      pdf.stroke_horizontal_rule
      pdf.move_down 8
    end

    def render_info(pdf)
      top = pdf.cursor
      pdf.text_box left_info,  at: [0, top],   width: 470, size: 9, inline_format: true, leading: 2
      pdf.text_box right_info, at: [480, top], width: pdf.bounds.width - 480, size: 9, inline_format: true, leading: 2
      pdf.move_cursor_to top - 70
      pdf.move_down 4
    end

    def render_items_table(pdf)
      header = ["Código", "Descripción", "Unidad", "Cantidad", "Precio",
                "Monto", "%Dto.", "Subtotal", "%IVA", "Total"]

      rows = @order.order_items.map do |i|
        [
          i.code, i.description, i.unit,
          amount(i.quantity), amount(i.unit_price), amount(i.line_total),
          pct(i.discount_percent), amount(i.taxable), pct(i.tax_rate), amount(i.total)
        ]
      end
      rows = [["—"] + [""] * 9] if rows.empty?

      pdf.table([header] + rows,
                header: true, column_widths: ITEM_COLUMN_WIDTHS,
                cell_style: { size: 8, padding: [3, 4, 3, 4], border_color: "999999", borders: [:top, :bottom, :left, :right] }) do
        row(0).font_style       = :bold
        row(0).background_color  = "EEEEEE"
        row(0).align             = :center
        columns(1).align         = :left
        columns(0).align         = :left
        columns(2).align         = :center
        [3, 4, 5, 6, 7, 8, 9].each { |c| columns(c).rows(1..-1).align = :right }
      end
      pdf.move_down 12
    end

    def render_footer(pdf)
      y = pdf.cursor
      # Importe en letra (izquierda)
      pdf.text_box amount_in_words(@order.total), at: [0, y + 4], width: 330, size: 9, style: :bold

      # Totales (derecha)
      rows = [
        ["Subtotal",  number_to_currency(@order.subtotal)],
        ["Descuento", number_to_currency(@order.discount_total)],
        ["IVA",       number_to_currency(@order.tax_total)],
        ["Total",     number_to_currency(@order.total)]
      ]
      pdf.bounding_box([pdf.bounds.right - 230, y], width: 230) do
        pdf.table(rows, cell_style: { borders: [], padding: [1, 6, 1, 6], size: 10 }) do
          column(0).font_style = :bold
          column(1).align      = :right
          column(1).font_style = :bold
          row(-1).borders          = [:top]
          row(-1).border_top_width = 0.5
          row(-1).size             = 12
          row(-1).padding          = [4, 6, 1, 6]
        end
      end
    end

    # ---- Bloques de texto -------------------------------------------------

    def left_info
      lines = ["<b>Cliente:</b>  (#{@order.client.erp_client_key})  #{@order.client.commercial_name.presence || @order.client.name}"]
      if @order.invoice?
        t = @order.client_tax_profile
        lines << "<b>POR FACTURAR</b>   RFC: #{t&.rfc}   Razón Social: #{t&.business_name}"
      else
        lines << "<b>REMISIÓN:</b>  #{@order.client_receipt_profile&.name}"
      end
      lines << "<b>Dirección:</b>  #{@order.client_branch&.address}" if @order.client_branch&.address.present?
      lines << "<b>Sucursal:</b>  #{@order.client_branch&.name}"
      lines << "<b>Uso CFDI:</b>  #{@order.cfdi_use.code} #{@order.cfdi_use.description}" if @order.invoice? && @order.cfdi_use
      lines.join("\n")
    end

    def right_info
      vendor = @order.client.salesperson
      [
        "Capturado: #{@order.created_at.strftime('%d/%m/%Y %H:%M')}    Renglones: #{@order.order_items.size}",
        ("Transmitido: #{@order.transmitted_at.strftime('%d/%m/%Y %H:%M')}" if @order.transmitted? && @order.transmitted_at),
        ("Vendedor: #{[vendor.erp_salesperson_id, vendor.name].compact.join(' ')}" if vendor),
        "Estatus: #{@order.status_label.upcase}"
      ].compact.join("\n")
    end

    # ---- Helpers ----------------------------------------------------------

    def date_only
      @order.created_at.strftime("%d/%m/%Y")
    end

    def amount(value)
      number_with_precision(value || 0, precision: 2, delimiter: ",")
    end

    def pct(value)
      number_to_percentage(value || 0, precision: 2)
    end

    def amount_in_words(total)
      entero   = total.to_i
      centavos = ((total - entero) * 100).round
      "#{integer_to_words(entero)} pesos #{format('%02d', centavos)}/100 M.N.".upcase
    end

    def integer_to_words(n)
      return "cero" if n.zero?

      millones = n / 1_000_000
      miles    = (n % 1_000_000) / 1_000
      cientos  = n % 1_000
      out = []
      out << (millones == 1 ? "un millon" : "#{hundreds_to_words(millones)} millones") if millones.positive?
      out << (miles == 1 ? "mil" : "#{hundreds_to_words(miles)} mil") if miles.positive?
      out << hundreds_to_words(cientos) if cientos.positive?
      out.join(" ")
    end

    def hundreds_to_words(n)
      return "cien" if n == 100

      centenas = ["", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos",
                  "seiscientos", "setecientos", "ochocientos", "novecientos"]
      parts = []
      parts << centenas[n / 100] if n >= 100
      parts << tens_to_words(n % 100) if (n % 100).positive?
      parts.join(" ")
    end

    def tens_to_words(n)
      unidades = ["", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve",
                  "diez", "once", "doce", "trece", "catorce", "quince", "dieciseis", "diecisiete",
                  "dieciocho", "diecinueve", "veinte", "veintiuno", "veintidos", "veintitres",
                  "veinticuatro", "veinticinco", "veintiseis", "veintisiete", "veintiocho", "veintinueve"]
      return unidades[n] if n <= 29

      decenas = ["", "", "", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa"]
      d = decenas[n / 10]
      u = n % 10
      u.zero? ? d : "#{d} y #{unidades[u]}"
    end
  end
end
