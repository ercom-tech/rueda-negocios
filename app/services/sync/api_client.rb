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

    private

    def get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      res = http.request(Net::HTTP::Get.new(uri))
      raise Error, "HTTP #{res.code} desde #{uri}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    rescue SystemCallError, SocketError, Timeout::Error, Net::ReadTimeout => e
      raise Error, "no se pudo conectar con rueda-api (#{uri}): #{e.message}"
    rescue JSON::ParserError
      # Respuesta 2xx con cuerpo no-JSON (proxy, HTML de error): error propio
      # para que el panel del server muestre el flash en vez de un 500 crudo.
      raise Error, "respuesta inválida de rueda-api (#{uri}): no es JSON"
    end
  end
end
