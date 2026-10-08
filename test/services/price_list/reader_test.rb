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
      assert_equal [ 3021 ], read(csv("CODIGO,PRECIO\n003021,6900\n")).rows.map(&:code)
    end

    test "un código en texto de más de 6 dígitos no es válido" do
      assert_equal [ "1234567" ], read(csv("CODIGO,PRECIO\n1234567,6900\n")).problems.map(&:code_text)
    end

    test "las columnas se buscan por encabezado, no por posición" do
      path = xlsx([ [ "x", 9, 3021, 6900 ] ], header: [ "Notas", "Existencia", "Código FECEGO", "Precio lista" ])

      row = read(path).rows.sole
      assert_equal [ 3021, BigDecimal("6900") ], [ row.code, row.price ]
    end

    test "encuentra el encabezado aunque tenga un título arriba" do
      path = xlsx([ [ 3021, 6900 ] ], before: [ [ "Lista Stihl octubre" ], [] ])

      assert_equal [ 3021 ], read(path).rows.map(&:code)
    end

    test "sin encabezados lo dice y no adivina columnas" do
      error = assert_raises(Error) { read(xlsx([ [ 3021, 6900 ] ], header: [ "A", "B" ])) }
      assert_match(/No encontré las columnas CODIGO y PRECIO/, error.message)
    end

    test "precio en texto con signo de pesos y miles" do
      assert_equal [ BigDecimal("1234.5") ], read(csv("CODIGO,PRECIO\n3021,\"$1,234.50\"\n")).rows.map(&:price)
    end

    test "redondea a 2 decimales, como la partida" do
      assert_equal [ BigDecimal("10.13") ], read(csv("CODIGO,PRECIO\n3021,10.125\n")).rows.map(&:price)
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
        [ 7, "003024", "El precio no es un número." ],
        [ 8, "003025", "El precio es demasiado grande." ]
      ], reader.problems.map { |p| [ p.line, p.code_text, p.reason ] }
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
      path = File.join(@dir, "precios.csv").tap { |p| File.binwrite(p, "C\xD3DIGO,PRECIO\r\n003021,6900\r\n".b) }

      assert_equal [ [ 3021, BigDecimal("6900") ] ], read(path).rows.map { |r| [ r.code, r.price ] }
    end

    test "lee el CSV con BOM y con punto y coma de separador" do
      path = File.join(@dir, "precios.csv").tap { |p| File.binwrite(p, "\xEF\xBB\xBFCODIGO;PRECIO\n3021;6900\n".b) }

      assert_equal [ 3021 ], read(path).rows.map(&:code)
    end

    # Antes reventaba como pantalla de error: roo lee el CSV hasta que se le
    # piden las celdas, fuera del rescate.
    test "un CSV mal formado da el mensaje de qué hacer, no una pantalla de error" do
      error = assert_raises(Error) { read(csv("CODIGO,PRECIO\n\"3021,10\n")) }
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
      path = csv("CODIGO,PRECIO\n" + "x" * 5.megabytes)

      error = assert_raises(Error) { read(path) }
      assert_match(/pesa más de 5 MB/, error.message)
    end

    test "rechaza más de 50,000 renglones" do
      path = csv("CODIGO,PRECIO\n" + "3021,10\n" * 50_001)

      error = assert_raises(Error) { read(path) }
      assert_match(/más de 50,000 renglones/, error.message)
    end
  end
end
