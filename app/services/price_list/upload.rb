require "fileutils"

module PriceList
  # Guarda el archivo subido entre "Revisar" y "Aplicar".
  #
  # El navegador no puede volver a mandar el archivo al confirmar, y la sesión
  # (cookie, 4 KB) no lo aguanta. Se guarda en disco bajo una ficha aleatoria,
  # y "Aplicar" lo vuelve a leer y a revisar: así se aplica lo que dice el
  # archivo CONTRA EL CATÁLOGO DE ESE MOMENTO, no una revisión vieja.
  #
  # Una carpeta por ficha, con el archivo dentro bajo su nombre original: el
  # nombre es lo que se registra como origen de cada precio.
  class Upload
    # Carpeta aparte en pruebas: las pruebas la vacían, y con la misma carpeta
    # borraban las revisiones en curso del servidor de desarrollo.
    ROOT = Rails.root.join("tmp", Rails.env.test? ? "price_lists_test" : "price_lists")
    TOKEN = /\A\h{32}\z/
    # Lo que se subió y nunca se aplicó se barre en la siguiente subida.
    TTL = 1.day

    attr_reader :token, :path, :filename

    def self.store(uploaded)
      sweep
      token = SecureRandom.hex(16)
      filename = safe_filename(uploaded.original_filename)
      dir = ROOT.join(token)
      FileUtils.mkdir_p(dir)
      FileUtils.cp(uploaded.path, dir.join(filename))
      new(token, dir.join(filename).to_s, filename)
    end

    # Solo el nombre, sin ruta y sin caracteres que estorben en disco. Sin
    # punto al inicio (un archivo oculto no lo ve `find`) y con tope de bytes
    # conservando la extensión: ext4, el de la laptop, no acepta nombres de
    # más de 255 bytes, y uno largo con acentos daba pantalla de error.
    MAX_FILENAME_BYTES = 150

    def self.safe_filename(original)
      name = File.basename(original.to_s).gsub(/[^\p{Alnum}._ -]/, "_")
      # ".csv" a secas: Ruby no lo ve como extensión, pero eso es lo que es.
      name = "precios#{name}" if name.match?(/\A\.[^.]+\z/)
      name = name.sub(/\A\.+/, "")
      extension = File.extname(name)
      base = File.basename(name, extension).presence || "precios"
      base = base.byteslice(0, MAX_FILENAME_BYTES).scrub("") if base.bytesize > MAX_FILENAME_BYTES
      "#{base}#{extension}"
    end

    # nil si la ficha no tiene forma de ficha (nunca se arma una ruta con lo
    # que venga en la URL) o si ya no existe.
    def self.find(token)
      return unless token.to_s.match?(TOKEN)

      path = Dir.glob(ROOT.join(token, "*").to_s).first
      new(token, path, File.basename(path)) if path
    end

    def self.sweep
      Dir.glob(ROOT.join("*").to_s).each do |dir|
        FileUtils.rm_rf(dir) if File.mtime(dir) < TTL.ago
      end
    end

    def initialize(token, path, filename)
      @token = token
      @path = path
      @filename = filename
    end

    def delete = FileUtils.rm_rf(ROOT.join(token))

    # Al aplicar, el archivo ya no hace falta, pero la ficha se recuerda como
    # aplicada (un marcador oculto, que `find` no ve) hasta el barrido: así
    # volver con "atrás" dice "ya se aplicó" y no "ya no está disponible".
    APPLIED_MARK = ".applied".freeze

    def mark_applied!
      FileUtils.rm_f(path)
      FileUtils.touch(ROOT.join(token, APPLIED_MARK))
    end

    def self.applied?(token)
      token.to_s.match?(TOKEN) && File.exist?(ROOT.join(token, APPLIED_MARK))
    end

    def read = Reader.read(path, filename:)
  end
end
