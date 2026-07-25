require "net/http"
require "json"

module Sync
  # Cliente HTTP hacia rueda-api. Encapsula las llamadas que consumen el rake
  # y los jobs del panel del servidor.
  class ApiClient
    class Error < StandardError; end

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
      res = Net::HTTP.get_response(uri)
      raise Error, "HTTP #{res.code} desde #{uri}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    rescue SystemCallError, SocketError, Timeout::Error => e
      raise Error, "no se pudo conectar con rueda-api (#{uri}): #{e.message}"
    end
  end
end
