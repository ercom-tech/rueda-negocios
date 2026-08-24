require "test_helper"

module Pdf
  class OrderGeneratorTest < ActiveSupport::TestCase
    # amount_in_words no depende del estado del pedido: se prueba directo.
    def words(total)
      OrderGenerator.allocate.send(:amount_in_words, total)
    end

    test "un total a precisión completa se cuantiza antes del importe en letra" do
      # Sin round(2), 100.999 daba "CIEN PESOS 100/100 M.N."
      assert_equal "CIENTO UN PESOS 00/100 M.N.", words(BigDecimal("100.999"))
    end

    test "centavos normales" do
      assert_equal "CUATROCIENTOS SETENTA Y UN PESOS 08/100 M.N.", words(BigDecimal("471.08"))
      assert_equal "CERO PESOS 50/100 M.N.", words(BigDecimal("0.50"))
    end

    test "miles de millones no truenan (recursión en millones)" do
      # El "DE" ante millones redondos: la prueba consagraba la forma sin él
      # ("MIL MILLONES PESOS"), que es la que va impresa al cliente. (5ª aud.)
      assert_equal "MIL MILLONES DE PESOS 00/100 M.N.", words(BigDecimal("1000000000"))
      assert_equal "UN MILLON DE PESOS 00/100 M.N.", words(BigDecimal("1000000"))
      assert_includes words(BigDecimal("2500000000.75")), "DOS MIL QUINIENTOS MILLONES"
    end

    test "un total de un peso concuerda en singular" do
      assert_equal "UN PESO 00/100 M.N.", words(BigDecimal("1"))
      assert_equal "UN PESO 50/100 M.N.", words(BigDecimal("1.50"))
      assert_equal "DOS PESOS 00/100 M.N.", words(BigDecimal("2"))
    end

    # --- El PDF de verdad ----------------------------------------------------
    # Hasta la 4ª auditoría, `render` no se ejecutaba ni una vez en la suite: es
    # el documento que se lleva el cliente y nadie lo miraba desde las pruebas.

    setup do
      @user   = User.create!(erp_person_id: 940_001, username: "cap940", password: "x",
                             role: "capturista", name: "ANA", paternal_surname: "LÓPEZ")
      @round  = BusinessRound.create!(erp_round_id: 940_001, name: "RUEDA PDF", active: true)
      @client = Client.create!(erp_client_key: "PDF01", name: "CLIENTE PDF",
                               commercial_name: "COMERCIAL PDF")
      @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    end

    def item!(quantity:, price:, discount: 0, tax: 16, description: "PRODUCTO")
      # Con producto: el descuento se valida contra su `max_discount`.
      product = Product.create!(erp_product_id: 940_000 + @order.order_items.count,
                                description: description, max_discount: 50)
      @order.order_items.create!(product: product, position: @order.order_items.count + 1,
                                 quantity: quantity, unit_price: price,
                                 discount_percent: discount, tax_rate: tax,
                                 code: "0001", description: description, unit: "PZA")
    end

    # Extrae el texto del PDF. Prawn emite cada tramo como cadena HEXADECIMAL
    # dentro de un arreglo `TJ` (los números intercalados son kerning), y los
    # acentos van en Windows-1252. Se descartan los streams sin texto — el del
    # logo son píxeles.
    def pdf_text(order = @order)
      raw = OrderGenerator.new(order.reload).render

      streams = raw.scan(/stream\r?\n(.*?)\r?\nendstream/m).flatten.filter_map do |chunk|
        # Prawn no comprime por omisión, pero puede hacerlo.
        content = begin
          Zlib::Inflate.inflate(chunk.b)
        rescue Zlib::Error
          chunk.b
        end
        content if content.include?("BT")
      end

      streams.join(" ").scan(/\[(.*?)\]\s*TJ/m).flatten.map do |chunks|
        chunks.scan(/<([0-9A-Fa-f]+)>/).flatten.map { |hex| [ hex ].pack("H*") }.join
      end.join(" ").force_encoding("Windows-1252").encode("UTF-8", invalid: :replace, undef: :replace)
    end

    test "el PDF se genera con partidas y sin ellas" do
      assert_predicate OrderGenerator.new(@order).render, :present?, "un pedido vacío no debe reventar"

      item!(quantity: 2, price: 100)
      assert_predicate OrderGenerator.new(@order.reload).render, :present?
    end

    # El único lugar del proyecto que formateaba sin `.localtime`: un pedido de
    # las 19:30 salía en el papel como del día siguiente a la 1:30.
    test "la fecha del PDF va en hora local, como el reporte y el ERP" do
      item!(quantity: 1, price: 100)
      @order.update_column(:created_at, ::Time.new(2026, 8, 11, 19, 30))

      texto = pdf_text
      esperado = @order.created_at.localtime.strftime("%d/%m/%Y")

      assert_includes texto, esperado
      assert_includes texto, @order.created_at.localtime.strftime("%d/%m/%Y %H:%M")
    end

    # El cliente cuadra su copia sumando la columna Total.
    test "la columna Total suma exactamente el Total del pie" do
      # Importes deliberadamente feos: sin cuantizar por partida, la deriva se
      # acumula y el pie no coincide con la suma de la columna.
      10.times { |i| item!(quantity: 3, price: BigDecimal("471.0#{i}"), discount: 5) }

      generator = OrderGenerator.new(@order.reload)
      generator.render # llena el memo de importes impresos
      items = generator.send(:printed_items)

      suma_columna = items.sum { |i| i[:total] }
      pie          = generator.send(:printed_total, :total)
      assert_equal suma_columna, pie

      # Y el pie cuadra consigo mismo: Subtotal − Descuento + IVA = Total.
      assert_equal pie, generator.send(:printed_total, :amount) -
                        generator.send(:printed_total, :discount) +
                        generator.send(:printed_total, :tax)
      assert_equal pie, pie.round(2), "el total impreso va a 2 decimales"
    end

    test "un pedido de 45 partidas numera todas sus páginas con el folio" do
      45.times { item!(quantity: 1, price: 1000) }
      @order.capture!

      texto = pdf_text

      assert_includes texto, "#{@order.folio} · Página 1 de 2"
      assert_includes texto, "#{@order.folio} · Página 2 de 2"
    end

    # `inline_format: true` hace que Prawn parsee el texto como su
    # mini-lenguaje de etiquetas: sin escapar, se come lo que va entre < y >.
    test "el texto capturado no se interpreta como marcado" do
      item!(quantity: 1, price: 100)
      @order.update!(observations: "ENTREGAR ANTES DE <5 DIAS>")

      assert_includes pdf_text, "ENTREGAR ANTES DE <5 DIAS>"
    end

    # El monto de división es una instrucción de facturación y el papel es lo
    # que llega a quien factura: sin él en el PDF, el dato solo vivía en la
    # pantalla y en el ERP.
    test "el monto de división de facturas se imprime" do
      DivideAmount.create!(erp_consecutive: 1, amount: 5000)
      @order.update!(dividir_facturas: 5000)
      item!(quantity: 1, price: 100)

      assert_includes pdf_text, "Dividir facturas cada"
      assert_includes pdf_text, "$5,000.00"
    end

    # Aplica a los DOS tipos: el ERP tiene 6,128 remisiones nativas con monto.
    # El pedido del setup es remisión, así que la prueba de arriba ya cubre ese
    # caso; esta fija que en factura también salga.
    test "también se imprime en una factura" do
      DivideAmount.create!(erp_consecutive: 1, amount: 2000)
      tax = @client.tax_profiles.create!(rfc: "XAXX010101000", business_name: "PUBLICO")
      cfdi = CfdiUse.create!(code: "G01", description: "Adquisición")
      @order.update!(kind: "invoice", client_tax_profile: tax, cfdi_use: cfdi,
                     client_receipt_profile: nil, dividir_facturas: 2000)
      item!(quantity: 1, price: 100)

      assert_includes pdf_text, "Dividir facturas cada"
      assert_includes pdf_text, "$2,000.00"
    end

    # 0 = "no dividir": imprimirlo sería una instrucción que no instruye nada.
    test "sin monto no se imprime la línea" do
      item!(quantity: 1, price: 100)

      assert_not_includes pdf_text, "Dividir facturas"
    end

    # Extraer el texto del stream NO basta para saber si se VE: la tabla de
    # partidas se dibuja después, y lo que quede bajo su borde superior queda
    # tapado aunque esté escrito. Lo que hay que medir es cuánto espacio
    # RESERVA `render_info` frente a lo que el bloque ocupa.
    def espacio_reservado_y_ocupado(order)
      gen = OrderGenerator.new(order)
      pdf = Prawn::Document.new(page_size: "LETTER", page_layout: :landscape, margin: [ 36, 36, 54, 36 ])
      pdf.font "Helvetica"
      top = pdf.cursor
      gen.send(:render_info, pdf)
      reservado = top - pdf.cursor
      ocupado   = gen.send(:text_height, pdf, gen.send(:left_info), 470)
      [ reservado, ocupado ]
    end

    # El caso que lo destapó: una factura con dirección larga suma RFC/Razón
    # Social y Uso CFDI, y su última línea —el monto de división— caía debajo
    # del inicio de la tabla, que la tapaba.
    test "la tabla no tapa el bloque de datos en el caso mas largo" do
      DivideAmount.create!(erp_consecutive: 1, amount: 5000)
      tax  = @client.tax_profiles.create!(rfc: "XAXX010101000",
                                          business_name: "PUBLICO EN GENERAL S.A. DE C.V.")
      cfdi = CfdiUse.create!(code: "G01", description: "Adquisición de mercancías")
      branch = @client.branches.create!(erp_branch_id: 1, name: "MATRIZ",
        address: "CRUCERO DE AYUTLA — CRUCERO DE AYUTLA S/N, COL. TIERRA COLORADA " \
                 "CENTRO, CP 39940, JUAN R. ESCUDERO, GUERRERO")
      @order.update!(kind: "invoice", client_tax_profile: tax, cfdi_use: cfdi,
                     client_receipt_profile: nil, client_branch: branch, dividir_facturas: 5000)

      reservado, ocupado = espacio_reservado_y_ocupado(@order)

      assert_operator ocupado, :>, OrderGenerator::INFO_MIN_HEIGHT,
                      "si este caso no rebasa el mínimo, la prueba no está midiendo el caso largo"
      assert_operator reservado, :>=, ocupado + OrderGenerator::INFO_GAP,
                      "la tabla arrancaría encima del bloque y taparía sus últimas líneas"
    end

    # Un pedido corto no debe encoger el bloque: el aire de siempre se conserva.
    test "un pedido corto conserva el espacio minimo" do
      item!(quantity: 1, price: 100)

      reservado, ocupado = espacio_reservado_y_ocupado(@order)

      assert_operator ocupado, :<, OrderGenerator::INFO_MIN_HEIGHT
      assert_equal OrderGenerator::INFO_MIN_HEIGHT + OrderGenerator::INFO_GAP, reservado
    end
  end
end
