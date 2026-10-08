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
    ROOT = Rails.root.join("tmp", "price_lists")
    TOKEN = /\A\h{32}\z/
    # Lo que se subió y nunca se aplicó se barre en la siguiente subida.
    TTL = 1.day

    attr_reader :token, :path, :filename

    def self.store(uploaded)
      sweep
      token = SecureRandom.hex(16)
      # Solo el nombre, sin ruta, y sin caracteres que estorben en disco.
      filename = File.basename(uploaded.original_filename.to_s).gsub(/[^\p{Alnum}._ -]/, "_").presence || "precios"
      dir = ROOT.join(token)
      FileUtils.mkdir_p(dir)
      FileUtils.cp(uploaded.path, dir.join(filename))
      new(token, dir.join(filename).to_s, filename)
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

    def read = Reader.read(path, filename:)
  end
end
