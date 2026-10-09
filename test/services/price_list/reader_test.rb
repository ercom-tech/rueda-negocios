require "test_helper"

module PriceList
  class ReaderTest < ActiveSupport::TestCase
    setup { @dir = Dir.mktmpdir }
    teardown { FileUtils.remove_entry(@dir) }

    # Un .xlsx de verdad, como lo guarda Excel: códigos numéricos (sin ceros) y
    # precios flotantes, salvo que la prueba pida otra cosa.
    def xlsx(rows, header: [ "CODIGO", "PRECIO LISTA S/IVA" ], before: [])
      path = File.join(@dir, "precios.xlsx")
      Axlsx::Package.new do |pkg|
        pkg.workbook.add_worksheet do |sheet|
          before.each { |r| sheet.add_row(r) }
          sheet.add_row(header)
          rows.each { |r| sheet.add_row(r) }
        end
        pkg.serialize(path)
      end
      path
    end

    def csv(text)
      File.join(@dir, "precios.csv").tap { |path| File.write(path, text) }
    end

    def read(path, filename: File.basename(path)) = Reader.read(path, filename:)

    test "lee el layout de FECEGO: código numérico sin ceros y precio flotante" do
      reader = read(xlsx([ [ 3021, 6900 ], [ 55872, 2058.9699999999998 ] ]))

      assert_equal [ 3021, 55872 ], reader.rows.map(&:code)
      assert_equal [ BigDecimal("6900"), BigDecimal("2058.97") ], reader.rows.map(&:price)
      assert_equal [ 2, 3 ], reader.rows.map(&:line), "la línea es la del archivo, para encontrarla en Excel"
      assert_empty reader.problems
    end

    test "el código en texto con ceros a la izquierda es el mismo código" do
      assert_equal [ 3021 ], read(csv("CODIGO,PRECIO LISTA S/IVA\n003021,6900\n")).rows.map(&:code)
    end

    test "un código en texto de más de 6 dígitos no es válido" do
      assert_equal [ "1234567" ], read(csv("CODIGO,PRECIO LISTA S/IVA\n1234567,6900\n")).problems.map(&:code_text)
    end

    # El formato se exige tal cual el layout (decisión del usuario, 13ª
    # auditoría): buscar "una columna que diga PRECIO" leía la primera —con
    # IVA, o el precio del ERP del CSV que exporta la propia pantalla.
    test "con dos columnas de precio rechaza el archivo en vez de elegir una" do
      path = xlsx([ [ 3021, 2388.41, 2058.97 ] ], header: [ "CODIGO", "PRECIO C/IVA", "PRECIO LISTA S/IVA" ])

      error = assert_raises(Error) { read(path) }
      assert_equal "El archivo no tiene el formato del layout: la primera fila debe llevar solo las columnas " \
                   "CODIGO (A) y PRECIO LISTA S/IVA (B). Este trae: «CODIGO», «PRECIO C/IVA», «PRECIO LISTA S/IVA».",
                   error.message
    end

    test "rechaza el CSV que exporta la propia pantalla de precios" do
      path = csv("Código,Descripción,Precio del ERP,Precio de rueda\n003021,MOTOSIERRA,6500.0,6900.0\n")

      assert_raises(Error) { read(path) }
    end

    test "exige los encabezados exactos, en su orden y en la primera fila" do
      [ [ "PRECIO LISTA S/IVA", "CODIGO" ], [ "CODIGO", "PRECIO" ], [ "Código FECEGO", "PRECIO LISTA S/IVA" ] ].each do |header|
        assert_raises(Error, header.inspect) { read(xlsx([ [ 3021, 6900 ] ], header:)) }
      end
      error = assert_raises(Error) { read(xlsx([ [ 3021, 6900 ] ], before: [ [ "Lista Stihl octubre" ] ])) }
      assert_match(/Este trae: «LISTA STIHL OCTUBRE»/, error.message)
    end

    test "tolera mayúsculas, acentos y espacios en los encabezados" do
      path = xlsx([ [ 3021, 6900 ] ], header: [ " Código ", "precio  lista s / iva" ])

      assert_equal [ 3021 ], read(path).rows.map(&:code)
    end

    test "con la primera fila vacía lo dice" do
      error = assert_raises(Error) { read(csv("\n3021,6900\n")) }
      assert_match(/Este la trae vacía\./, error.message)
    end

    test "rechaza datos fuera de las columnas A y B, aunque el encabezado esté bien" do
      error = assert_raises(Error) { read(csv("CODIGO,PRECIO LISTA S/IVA\n3021,6900\n3022,10,nota\n")) }
      assert_match(/el renglón 3 trae datos fuera de las columnas A y B/, error.message)

      error = assert_raises(Error) { read(xlsx([ [ 3021, 6900, nil, "nota" ] ])) }
      assert_match(/trae datos en la columna D\./, error.message)
    end

    # Una celda con algo en una columna lejana hacía armar una tabla de miles
    # de millones de celdas antes de revisar el tope (13ª auditoría). Se
    # rechaza midiendo la hoja, sin leerla.
    test "una celda en una columna lejana se rechaza sin leer la hoja" do
      path = xlsx([ [ 3021, 6900 ] ])
      sheet_xml = nil
      Zip::File.open(path) do |zip|
        sheet_xml = zip.read("xl/worksheets/sheet1.xml")
          .sub("</sheetData>", '<row r="40000"><c r="XFD40000"><v>1</v></c></row></sheetData>')
        zip.get_output_stream("xl/worksheets/sheet1.xml") { |f| f.write(sheet_xml) }
      end

      started = Time.current
      error = assert_raises(Error) { read(path) }
      assert_match(/trae datos en la columna XFD\./, error.message)
      assert_operator Time.current - started, :<, 3, "no debe armar la tabla"
    end

    test "un xlsx con un renglón lejano se rechaza por renglones sin leer la hoja" do
      path = xlsx([ [ 3021, 6900 ] ])
      Zip::File.open(path) do |zip|
        sheet_xml = zip.read("xl/worksheets/sheet1.xml")
          .sub("</sheetData>", '<row r="60000"><c r="A60000"><v>1</v></c></row></sheetData>')
        zip.get_output_stream("xl/worksheets/sheet1.xml") { |f| f.write(sheet_xml) }
      end

      error = assert_raises(Error) { read(path) }
      assert_match(/más de 50,000 renglones/, error.message)
    end

    test "un CSV con un renglón de muchísimas columnas se rechaza sin partirlo" do
      error = assert_raises(Error) { read(csv("CODIGO,PRECIO LISTA S/IVA\n" + "," * 100_000 + "\n")) }
      assert_match(/renglones con muchas columnas/, error.message)
    end

    test "precio en texto con signo de pesos y miles" do
      assert_equal [ BigDecimal("1234.5") ], read(csv("CODIGO,PRECIO LISTA S/IVA\n3021,\"$1,234.50\"\n")).rows.map(&:price)
    end

    # Una sola forma, sea cual sea el separador del CSV (decisión del usuario,
    # 13ª auditoría). Antes se borraban todas las comas: "2058,97" se leía
    # como 205897.
    test "el precio va con punto decimal y coma de miles" do
      reader = read(csv("CODIGO,PRECIO LISTA S/IVA\n3021,\"1,234.50\"\n3022,\"$12,345\"\n3023,99.9\n"))
      assert_equal %w[1234.5 12345.0 99.9], reader.rows.map { |r| r.price.to_s("F") }

      reader = read(csv("CODIGO;PRECIO LISTA S/IVA\n3021;1,234.50\n3022;2058.97\n"))
      assert_equal %w[1234.5 2058.97], reader.rows.map { |r| r.price.to_s("F") }, "también con punto y coma"
    end

    test "la coma decimal y las formas ambiguas se rechazan en vez de adivinar" do
      reader = read(csv("CODIGO;PRECIO LISTA S/IVA\n3021;2058,97\n3022;1.234,50\n3023;12,34,5\n3024;1,23\n"))

      assert_empty reader.rows
      assert_equal [ "El precio no es un número: usa punto para decimales y coma para miles (1,234.50)." ] * 4,
                   reader.problems.map(&:reason)
    end

    test "un archivo con solo el encabezado se rechaza" do
      [ "CODIGO,PRECIO LISTA S/IVA\n", "CODIGO,PRECIO LISTA S/IVA\n,\n\n" ].each do |text|
        error = assert_raises(Error) { read(csv(text)) }
        assert_equal "El archivo no trae renglones de precios.", error.message
      end
    end

    # Un XML con entidades anidadas desborda la pila de nokogiri: no es
    # StandardError y salía como pantalla de error (13ª auditoría).
    test "un xlsx con entidades anidadas da el mensaje de qué hacer" do
      path = xlsx([ [ 3021, 6900 ] ])
      entities = (1..9).map { |i| "<!ENTITY l#{i} \"#{"&l#{i - 1};" * 10}\">" }.join
      bomb = "<?xml version=\"1.0\"?><!DOCTYPE w [<!ENTITY l0 \"lol\">#{entities}]>"
      Zip::File.open(path) do |zip|
        xml = zip.read("xl/worksheets/sheet1.xml").sub(/\A<\?xml[^>]*\?>/, bomb).sub("<sheetData>", "<sheetData>&l9;")
        zip.get_output_stream("xl/worksheets/sheet1.xml") { |f| f.write(xml) }
      end

      error = assert_raises(Error) { read(path) }
      assert_equal Reader::UNREADABLE, error.message
    end

    test "redondea a 2 decimales, como la partida" do
      assert_equal [ BigDecimal("10.13") ], read(csv("CODIGO,PRECIO LISTA S/IVA\n3021,10.125\n")).rows.map(&:price)
    end

    test "los renglones vacíos se ignoran sin reportarse" do
      reader = read(xlsx([ [ 3021, 6900 ], [ nil, nil ], [ 3022, 10 ] ]))

      assert_equal 2, reader.rows.size
      assert_empty reader.problems
    end

    test "reporta cada renglón inválido con su línea y su motivo, y sigue con los demás" do
      reader = read(xlsx([ [ 3021, nil ], [ 3022, 0 ], [ 3023, -5 ], [ 1_234_567, 10 ],
                           [ "ABC", 10 ], [ 3024, "barato" ], [ 3025, 10**10 ], [ 3026, 15 ] ]))

      assert_equal [ 3026 ], reader.rows.map(&:code)
      assert_equal [
        [ 2, "003021", "No trae precio." ],
        [ 3, "003022", "El precio tiene que ser mayor a cero." ],
        [ 4, "003023", "El precio tiene que ser mayor a cero." ],
        [ 5, "1234567", "El código no es válido: deben ser hasta 6 dígitos." ],
        [ 6, "ABC", "El código no es válido: deben ser hasta 6 dígitos." ],
        [ 7, "003024", "El precio no es un número: usa punto para decimales y coma para miles (1,234.50)." ],
        [ 8, "003025", "El precio es demasiado grande." ]
      ], reader.problems.map { |p| [ p.line, p.code_text, p.reason ] }
      assert_equal %i[no_price no_price no_price invalid_code invalid_code invalid_price invalid_price],
                   reader.problems.map(&:kind), "el tipo agrupa los motivos para el desglose"
    end

    test "un código con decimales no es un código" do
      assert_equal [ "El código no es válido: deben ser hasta 6 dígitos." ],
                   read(xlsx([ [ 3021.5, 10 ] ])).problems.map(&:reason)
    end

    test "rechaza otros formatos con un mensaje que dice cuáles sirven" do
      path = File.join(@dir, "precios.pdf").tap { |p| File.write(p, "x") }

      error = assert_raises(Error) { read(path) }
      assert_match(/tiene que ser de Excel \(\.xlsx\) o CSV/, error.message)
    end

    test "un archivo dañado da un mensaje de qué hacer, no la excepción" do
      path = File.join(@dir, "precios.xlsx").tap { |p| File.write(p, "no soy un zip") }

      error = assert_raises(Error) { read(path) }
      assert_equal "No se pudo leer el archivo. Ábrelo en Excel y guárdalo de nuevo como .xlsx.", error.message
    end

    # Así sale un "CSV" de Excel en Windows en México: Windows-1252, con el
    # acento de CÓDIGO en un byte que no es UTF-8.
    test "lee el CSV de Excel en Windows-1252, con acentos en el encabezado" do
      path = File.join(@dir, "precios.csv").tap { |p| File.binwrite(p, "C\xD3DIGO,PRECIO LISTA S/IVA\r\n003021,6900\r\n".b) }

      assert_equal [ [ 3021, BigDecimal("6900") ] ], read(path).rows.map { |r| [ r.code, r.price ] }
    end

    test "lee el CSV con BOM y con punto y coma de separador" do
      path = File.join(@dir, "precios.csv").tap { |p| File.binwrite(p, "\xEF\xBB\xBFCODIGO;PRECIO LISTA S/IVA\n3021;6900\n".b) }

      assert_equal [ 3021 ], read(path).rows.map(&:code)
    end

    # Antes reventaba como pantalla de error: roo lee el CSV hasta que se le
    # piden las celdas, fuera del rescate.
    test "un CSV mal formado da el mensaje de qué hacer, no una pantalla de error" do
      error = assert_raises(Error) { read(csv("CODIGO,PRECIO LISTA S/IVA\n\"3021,10\n")) }
      assert_equal Reader::UNREADABLE, error.message
    end

    test "un zip que no es libro de Excel da el mensaje de qué hacer" do
      path = File.join(@dir, "precios.xlsx")
      Zip::File.open(path, create: true) { |zip| zip.get_output_stream("x.txt") { |f| f.write("hola") } }

      error = assert_raises(Error) { read(path) }
      assert_equal Reader::UNREADABLE, error.message
    end

    # Pasó el 2026-10-08: el servidor corría sin la gema cargada, y el rescate
    # de "todo" le dijo al operador que su archivo estaba dañado. Una falla del
    # sistema tiene que verse como tal.
    test "una falla del sistema no se disfraza de archivo dañado" do
      path = xlsx([ [ 3021, 6900 ] ])
      original = Roo::Spreadsheet.method(:open)
      Roo::Spreadsheet.define_singleton_method(:open) { |*| raise NameError, "uninitialized constant Roo" }

      assert_raises(NameError) { read(path) }
    ensure
      Roo::Spreadsheet.define_singleton_method(:open, original)
    end

    test "rechaza un archivo demasiado grande" do
      path = csv("CODIGO,PRECIO LISTA S/IVA\n" + "x" * 5.megabytes)

      error = assert_raises(Error) { read(path) }
      assert_match(/pesa más de 5 MB/, error.message)
    end

    test "rechaza más de 50,000 renglones" do
      path = csv("CODIGO,PRECIO LISTA S/IVA\n" + "3021,10\n" * 50_001)

      error = assert_raises(Error) { read(path) }
      assert_match(/más de 50,000 renglones/, error.message)
    end
  end
end
