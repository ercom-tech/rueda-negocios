require "csv"

module PriceList
  # Lee el archivo de precios (.xlsx o .csv) que se carga en el panel del
  # servidor (2026-10-08) y lo deja en renglones limpios, sin consultar nada:
  # comparar contra el catálogo es trabajo de `Review`.
  #
  # El layout es EXACTAMENTE el de FECEGO ("Cambio precio de lista
  # Stihl.xlsx"), decisión del usuario (13ª auditoría, 2026-10-09): la primera
  # fila trae CODIGO en la columna A y PRECIO LISTA S/IVA en la B, y nada más.
  # Cuando se buscaba "una columna que diga PRECIO", un archivo con PRECIO
  # C/IVA antes del S/IVA cargaba todo 16% arriba sin que nada lo señalara, y
  # el CSV que exporta la propia pantalla ("Precio del ERP" antes de "Precio de
  # rueda") revertía los precios cargados al volver a subirlo. Con el formato
  # exigido no hay columna que adivinar.
  class Reader
    EXTENSIONS = %w[xlsx csv].freeze
    MAX_BYTES  = 5.megabytes
    MAX_ROWS   = 50_000
    # Los encabezados del layout, ya normalizados (ver `normalize`).
    HEADERS = [ "CODIGO", "PRECIO LISTA S/IVA" ].freeze
    # Un CSV con más separadores que esto en un renglón no es el layout: se
    # rechaza ANTES de partirlo (un solo renglón de comas tardaba 21 s).
    MAX_SEPARATORS_PER_LINE = 20

    Row     = Data.define(:line, :code, :price)
    # `kind` agrupa los motivos para el desglose de la revisión ("3 fuera de la
    # rueda · 17 sin precio") sin depender de la redacción de `reason`.
    Problem = Data.define(:line, :code_text, :reason, :kind)

    attr_reader :rows, :problems

    def self.read(path, filename:) = new(path, filename).read!

    def initialize(path, filename)
      @path = path
      @filename = filename.to_s
      @rows = []
      @problems = []
    end

    def read!
      extension = File.extname(@filename).delete(".").downcase
      unless EXTENSIONS.include?(extension)
        raise Error, "El archivo tiene que ser de Excel (.xlsx) o CSV. El que subiste es «#{@filename}»."
      end
      raise Error, "El archivo pesa más de 5 MB. Revisa que sea la lista de precios." if File.size(@path) > MAX_BYTES

      table = extension == "csv" ? read_csv : read_xlsx
      check_header!(table.first || [])
      table.drop(1).each_with_index { |(code, price), index| read_line(index + 2, code, price) }
      self
    end

    UNREADABLE = "No se pudo leer el archivo. Ábrelo en Excel y guárdalo de nuevo como .xlsx.".freeze

    private

    # El archivo se lee COMPLETO aquí, a una tabla en memoria: roo lee
    # perezosamente, y un archivo dañado reventaba después, fuera de este
    # rescate, como pantalla de error. Y se rescata SOLO lo que significa
    # "archivo dañado": rescatar todo convertía una falla del sistema (la gema
    # sin cargar, 2026-10-08) en "guárdalo de nuevo", y mandaba a revisar un
    # archivo que estaba bien.
    #
    # El tamaño de la hoja se mide ANTES de leerla: una sola celda con algo en
    # una columna o un renglón lejanos (XFD1048576) hacía armar una tabla de
    # miles de millones de celdas, y el tope llegaba tarde (13ª auditoría).
    # Después se leen solo A y B, celda por celda desde el renglón 1.
    def read_xlsx
      sheet = Roo::Spreadsheet.open(@path, extension: :xlsx).sheet(0)
      return [] unless sheet.last_row

      last_column = sheet.last_column.to_i
      if last_column > HEADERS.size
        header = (1..[ last_column, 6 ].min).map { |col| sheet.cell(1, col) }
        check_header!(header)
        raise Error, "El archivo no tiene el formato del layout: trae datos en la columna " \
                     "#{Roo::Utils.number_to_letter(last_column)}. Deja solo CODIGO (A) y PRECIO LISTA S/IVA (B)."
      end
      check_rows!(sheet.last_row - 1)
      (1..sheet.last_row).map { |line| [ sheet.cell(line, 1), sheet.cell(line, 2) ] }
    rescue Zip::Error, Nokogiri::XML::SyntaxError, ArgumentError => e
      # ArgumentError: así avisa roo de un zip que no es libro de Excel
      # ("missing required workbook file").
      unreadable!(e)
    end

    # El CSV lo lee Ruby directo, no roo, para aceptar lo que Excel produce en
    # México: "CSV" de Excel en Windows sale en Windows-1252 (CÓDIGO con acento
    # en un byte que no es UTF-8), a veces con BOM, y según la configuración
    # regional con ";" en vez de ",".
    def read_csv
      text = File.binread(@path).delete_prefix("\xEF\xBB\xBF".b)
      text = text.dup.force_encoding(Encoding::UTF_8)
      text = text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8) unless text.valid_encoding?
      first_line = text.lines.first.to_s
      separator = first_line.count(";") > first_line.count(",") ? ";" : ","
      if text.each_line.any? { |line| line.count(separator) > MAX_SEPARATORS_PER_LINE }
        raise Error, "El archivo no tiene el formato del layout: trae renglones con muchas columnas. " \
                     "Deja solo CODIGO (A) y PRECIO LISTA S/IVA (B)."
      end
      check_rows!(text.count("\n") - 1)

      table = CSV.parse(text, col_sep: separator)
      check_header!(table.first || [])
      extra = table.index { |cells| cells.drop(HEADERS.size).any? { |cell| !blank?(cell) } }
      if extra
        raise Error, "El archivo no tiene el formato del layout: el renglón #{extra + 1} trae datos fuera de las " \
                     "columnas A y B. Deja solo CODIGO y PRECIO LISTA S/IVA."
      end
      table
    rescue CSV::MalformedCSVError, EncodingError => e
      unreadable!(e)
    end

    def check_rows!(count)
      return if count <= MAX_ROWS

      raise Error, "El archivo trae más de #{MAX_ROWS.to_fs(:delimited)} renglones. Revisa que sea la lista de precios."
    end

    # La primera fila tiene que ser exactamente el encabezado del layout.
    # Tolera solo lo que no cambia el significado: mayúsculas, acentos
    # (CÓDIGO) y espacios. Las celdas vacías a la derecha no cuentan.
    def check_header!(cells)
      names = cells.map { |cell| normalize(cell) }
      names.pop while names.any? && names.last.empty?
      return if names == HEADERS

      found = names.reject(&:empty?).map { |name| "«#{name}»" }
      raise Error, "El archivo no tiene el formato del layout: la primera fila debe llevar solo las columnas " \
                   "CODIGO (A) y PRECIO LISTA S/IVA (B). " +
                   (found.any? ? "Este trae: #{found.join(', ')}." : "Este la trae vacía.")
    end

    def unreadable!(error)
      Rails.logger.warn("[price_list] no se pudo leer #{@filename}: #{error.class}: #{error.message}")
      raise Error, UNREADABLE
    end

    def normalize(cell) = I18n.transliterate(cell.to_s).upcase.gsub(%r{\s*/\s*}, "/").squish

    def read_line(line, raw_code, raw_price)
      return if blank?(raw_code) && blank?(raw_price)

      code  = parse_code(raw_code)
      # Como lo muestra el ERP (6 dígitos) cuando es un código; si no, tal cual
      # venía, para que se encuentre en el archivo.
      code_text = code ? format("%06d", code) : raw_code.to_s.strip
      price = parse_price(raw_price)
      kind, reason =
        if code.nil? then [ :invalid_code, "El código no es válido: deben ser hasta 6 dígitos." ]
        elsif price.nil? && blank?(raw_price) then [ :no_price, "No trae precio." ]
        elsif price.nil? then [ :invalid_price, "El precio no es un número." ]
        elsif !price.positive? then [ :no_price, "El precio tiene que ser mayor a cero." ]
        elsif price >= OrderItem::MAX_UNIT_PRICE then [ :invalid_price, "El precio es demasiado grande." ]
        end
      return @problems << Problem.new(line:, code_text:, reason:, kind:) if reason

      @rows << Row.new(line:, code:, price:)
    end

    def blank?(value) = value.nil? || value.to_s.strip.empty?

    # Excel guarda el código como NÚMERO y se come los ceros a la izquierda
    # (003021 llega como 3021); en texto puede venir con ellos. Las dos formas
    # son el mismo código.
    def parse_code(value)
      code =
        case value
        when Integer then value
        when Float then value.to_i if value == value.floor
        when String then value.strip.to_i if value.strip.match?(/\A\d{1,6}\z/)
        end
      code if code&.between?(1, 999_999)
    end

    # A 2 decimales, como la partida. `to_s` y no el flotante directo: Excel
    # guarda 2058.97 como 2058.9699999999998, y `Float#to_s` ya da "2058.97".
    # En texto se aceptan "$" y separadores de miles ("$1,234.50").
    def parse_price(value)
      text =
        case value
        when Numeric then value.to_s
        when String then value.strip.delete("$, ")
        end
      return unless text&.match?(/\A-?\d+(\.\d+)?\z/)

      BigDecimal(text).round(2)
    end
  end
end
