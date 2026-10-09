require "csv"

module PriceList
  # Lee el archivo de precios (.xlsx o .csv) que se carga en el panel del
  # servidor (2026-10-08) y lo deja en renglones limpios, sin consultar nada:
  # comparar contra el catálogo es trabajo de `Review`.
  #
  # El layout es el de FECEGO ("Cambio precio de lista Stihl.xlsx"): una
  # columna CODIGO y una PRECIO LISTA S/IVA. Las columnas se buscan por su
  # ENCABEZADO y no por posición, para que una columna extra a la izquierda no
  # cambie en silencio qué se lee como precio.
  class Reader
    EXTENSIONS = %w[xlsx csv].freeze
    MAX_BYTES  = 5.megabytes
    MAX_ROWS   = 50_000
    # El encabezado puede no estar en la primera fila (un título arriba).
    HEADER_SEARCH_ROWS = 10

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
      header_index, code_col, price_col = locate_header(table)
      if table.size - header_index - 1 > MAX_ROWS
        raise Error, "El archivo trae más de #{MAX_ROWS.to_fs(:delimited)} renglones. Revisa que sea la lista de precios."
      end

      table.each_with_index.drop(header_index + 1).each do |cells, index|
        read_line(index + 1, cells[code_col], cells[price_col])
      end
      self
    end

    private

    UNREADABLE = "No se pudo leer el archivo. Ábrelo en Excel y guárdalo de nuevo como .xlsx.".freeze

    # El archivo se lee COMPLETO aquí, a una tabla en memoria: roo lee
    # perezosamente, y un archivo dañado reventaba después, fuera de este
    # rescate, como pantalla de error. Y se rescata SOLO lo que significa
    # "archivo dañado": rescatar todo convertía una falla del sistema (la gema
    # sin cargar, 2026-10-08) en "guárdalo de nuevo", y mandaba a revisar un
    # archivo que estaba bien.
    #
    # Celda por celda desde la columna A, para que el índice de cada columna
    # sea el de Excel sin depender de dónde empiecen los datos.
    def read_xlsx
      sheet = Roo::Spreadsheet.open(@path, extension: :xlsx).sheet(0)
      return [] unless sheet.last_row

      columns = 1..sheet.last_column.to_i
      (1..sheet.last_row).map { |line| columns.map { |col| sheet.cell(line, col) } }
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
      CSV.parse(text, col_sep: separator)
    rescue CSV::MalformedCSVError, EncodingError => e
      unreadable!(e)
    end

    def unreadable!(error)
      Rails.logger.warn("[price_list] no se pudo leer #{@filename}: #{error.class}: #{error.message}")
      raise Error, UNREADABLE
    end

    def locate_header(table)
      table.first(HEADER_SEARCH_ROWS).each_with_index do |cells, index|
        names = cells.map { |cell| normalize(cell) }
        code_col  = names.index { |c| c.start_with?("CODIGO") }
        price_col = names.index { |c| c.include?("PRECIO") }
        return [ index, code_col, price_col ] if code_col && price_col
      end
      raise Error, "No encontré las columnas CODIGO y PRECIO. La primera fila del archivo tiene que " \
                   "llevar esos encabezados, como en el layout de ejemplo."
    end

    def normalize(cell) = I18n.transliterate(cell.to_s).upcase.strip

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
