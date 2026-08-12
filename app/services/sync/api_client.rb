require "net/http"
require "json"

module Sync
  # Cliente HTTP hacia rueda-api. Encapsula las llamadas que consumen el rake
  # y los jobs del panel del servidor.
  class ApiClient
    class Error < StandardError; end

    # Timeouts (segundos). El export (13k productos) necesita un read amplio;
    # ambos configurables por ENV para afinarlos según la red del evento.
    OPEN_TIMEOUT = Integer(ENV.fetch("RUEDA_API_OPEN_TIMEOUT", 10))
    READ_TIMEOUT = Integer(ENV.fetch("RUEDA_API_READ_TIMEOUT", 120))

    def initialize(api_base = ENV["RUEDA_API_URL"])
      raise Error, "RUEDA_API_URL no configurada" if api_base.to_s.strip.empty?

      @root = api_base.end_with?("/") ? api_base : "#{api_base}/"
    end

    # Ruedas disponibles en el ERP (para elegir cuál trabajar).
    def list_rounds
      get(URI.join(@root, "ruedas"))
    end

    # Dataset completo de una rueda (fuente del sync-down).
    def fetch_export(round_erp_id)
      get(URI.join(@root, "ruedas/#{round_erp_id}/export"))
    end

    # Alta de un pedido en el ERP. Devuelve la respuesta cruda —a diferencia de
    # `get`— porque el sync-up necesita el código y el cuerpo de CADA pedido
    # para reportar por qué se rechazó, y un lote no se aborta por uno malo.
    # Las excepciones de red se dejan pasar: `Sync::Up` las traduce a un motivo
    # legible por pedido.
    def post(path, payload)
      uri = URI.join(@root, path)
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = payload.to_json
      http(uri).request(request)
    end

    private

    # Punto ÚNICO de configuración del transporte. Importa para la fase de
    # strengthening: el día que entren los tokens o el TLS, se agregan aquí y
    # los cubren todas las llamadas. Antes el sync-up armaba su propio
    # Net::HTTP y se habría quedado sin credenciales — justo la ruta de
    # escritura al ERP, la de mayor riesgo, y el síntoma habría sido un 401 en
    # plena oficina, no un error de compilación.
    def http(uri)
      client = Net::HTTP.new(uri.host, uri.port)
      client.open_timeout = OPEN_TIMEOUT
      client.read_timeout = READ_TIMEOUT
      client
    end

    def get(uri)
      res = http(uri).request(Net::HTTP::Get.new(uri))
      raise Error, error_message(res, uri) unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    rescue SystemCallError, SocketError, Timeout::Error, Net::ReadTimeout => e
      raise Error, "no se pudo conectar con rueda-api (#{uri}): #{e.message}"
    rescue JSON::ParserError
      # Respuesta 2xx con cuerpo no-JSON (proxy, HTML de error): error propio
      # para que el panel del server muestre el flash en vez de un 500 crudo.
      raise Error, "respuesta inválida de rueda-api (#{uri}): no es JSON"
    end

    # El mensaje de negocio de la API cuando lo trae ({error, message} — p.ej.
    # el 404 de "no hay ninguna rueda N vigente"), o el código pelón: "HTTP
    # 404" a secas no le dice al operador que lo roto es el número de rueda.
    def error_message(res, uri)
      message = JSON.parse(res.body)["message"]
      message.presence || "HTTP #{res.code} desde #{uri}"
    rescue JSON::ParserError, TypeError
      "HTTP #{res.code} desde #{uri}"
    end
  end
end
