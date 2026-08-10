require "net/http"
require "json"

namespace :sync do
  desc "Descarga el dataset de la rueda desde rueda-api y puebla el Postgres local (idempotente). ENV: RUEDA_API_URL, RUEDA_ID"
  task down: :environment do
    base = ENV.fetch("RUEDA_API_URL") { abort "Falta RUEDA_API_URL (base de rueda-api, p.ej. http://localhost:4568)" }
    id   = ENV.fetch("RUEDA_ID")      { abort "Falta RUEDA_ID (id_rueda del ERP a descargar)" }

    puts "[sync:down] descargando rueda #{id} desde #{base}"
    data = begin
      Sync::ApiClient.new(base).fetch_export(id)
    rescue Sync::ApiClient::Error => e
      abort "[sync:down] #{e.message}"
    end
    puts "[sync:down] descargado (#{data['products']&.size || 0} productos)"

    result = nil
    begin
      ActiveRecord::Base.transaction do
        result = Sync::Down.new(data).run!
      end
    rescue Sync::Down::GuardError => e
      abort "[sync:down] abortado: #{e.message}"
    end

    s = result.summary
    puts "[sync:down] entidades:"
    s[:entities].each { |table, n| puts format("  %-24s %d", table, n) }
    puts "[sync:down] usuarios omitidos (sin credencial): #{s[:skipped_users].size} #{s[:skipped_users].inspect if s[:skipped_users].any?}"
    puts "[sync:down] capturistas eliminados (fuera de la rueda): #{s[:removed_users].size} #{s[:removed_users].inspect if s[:removed_users].any?}"
    puts "[sync:down] SKUs omitidos (proveedor fuera de la rueda): #{s[:skipped_skus]}"
    puts "[sync:down] listo."
  end

  desc "Transmite los pedidos capturados al ERP vía rueda-api (idempotente). ENV: RUEDA_API_URL"
  task up: :environment do
    base = ENV.fetch("RUEDA_API_URL") { abort "Falta RUEDA_API_URL (base de rueda-api, p.ej. http://localhost:4568)" }

    pending = Order.captured.where(erp_folio: nil).count
    puts "[sync:up] pedidos por transmitir: #{pending}"

    r = begin
      Sync::Up.new(base).run!
    rescue Sync::Up::GuardError => e
      abort "[sync:up] abortado: #{e.message} Deben finalizarse o descartarse antes de transmitir."
    end

    r[:transmitted].each { |t| puts "  ✓ #{t[:local]} → folio ERP #{t[:erp]}" }
    r[:failed].each      { |f| puts "  ✗ #{f[:local]} (HTTP #{f[:status]}): #{f[:error]}" }
    puts "[sync:up] transmitidos: #{r[:transmitted].size}, fallidos: #{r[:failed].size}"
    abort "[sync:up] hubo pedidos fallidos." if r[:failed].any?
    puts "[sync:up] listo."
  end
end
