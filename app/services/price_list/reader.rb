require "csv"

module PriceList
  # Error que se le muestra tal cual al operador: el archivo no se pudo usar.
  class Error < StandardError; end

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
    Problem = Data.define(:line, :code_text, :reason)

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

      sheet = open_sheet(extension)
      header_line, code_col, price_col = locate_header(sheet)
      last = sheet.last_row.to_i
      if last - header_line > MAX_ROWS
        raise Error, "El archivo trae más de #{MAX_ROWS.to_fs(:delimited)} renglones. Revisa que sea la lista de precios."
      end

      ((header_line + 1)..last).each { |line| read_line(line, sheet.cell(line, code_col), sheet.cell(line, price_col)) }
      self
    end

    private

    # Roo levanta excepciones de bajo nivel (zip, XML, CSV) con un archivo
    # dañado o que solo tiene la extensión: al operador le sirve saber qué
    # hacer, no cuál de ellas fue.
    def open_sheet(extension)
      book = Roo::Spreadsheet.open(@path, extension: extension.to_sym)
      book.sheet(0)
    rescue StandardError => e
      Rails.logger.warn("[price_list] no se pudo abrir #{@filename}: #{e.class}: #{e.message}")
      raise Error, "No se pudo leer el archivo. Ábrelo en Excel y guárdalo de nuevo como .xlsx."
    end

    def locate_header(sheet)
      first = sheet.first_row.to_i
      (first...(first + HEADER_SEARCH_ROWS)).each do |line|
        cells = Array(sheet.row(line)).map { |cell| normalize(cell) }
        code_col  = cells.index { |c| c.start_with?("CODIGO") }
        price_col = cells.index { |c| c.include?("PRECIO") }
        return [ line, code_col + 1, price_col + 1 ] if code_col && price_col
      end
      raise Error, "No encontré las columnas CODIGO y PRECIO. La primera fila del archivo tiene que " \
                   "llevar esos encabezados, como en el layout de ejemplo."
    end

    def normalize(cell) = I18n.transliterate(cell.to_s).upcase.strip

    def read_line(line, raw_code, raw_price)
      return if blank?(raw_code) && blank?(raw_price)

      code_text = raw_code.is_a?(Float) && raw_code == raw_code.floor ? raw_code.to_i.to_s : raw_code.to_s.strip
      code  = parse_code(raw_code)
      price = parse_price(raw_price)
      reason =
        if code.nil? then "El código no es válido: deben ser hasta 6 dígitos."
        elsif price.nil? then blank?(raw_price) ? "No trae precio." : "El precio no es un número."
        elsif !price.positive? then "El precio tiene que ser mayor a cero."
        elsif price >= OrderItem::MAX_UNIT_PRICE then "El precio es demasiado grande."
        end
      return @problems << Problem.new(line:, code_text:, reason:) if reason

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
