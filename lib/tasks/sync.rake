require "net/http"
require "json"

namespace :sync do
  desc "Descarga el dataset de la rueda desde rueda-api y puebla el Postgres local (idempotente). ENV: RUEDA_API_URL, RUEDA_ID"
  task down: :environment do
    base = ENV.fetch("RUEDA_API_URL") { abort "Falta RUEDA_API_URL (base de rueda-api, p.ej. http://localhost:4568)" }
    id   = ENV.fetch("RUEDA_ID")      { abort "Falta RUEDA_ID (id_rueda del ERP a descargar)" }

    root = base.end_with?("/") ? base : "#{base}/"
    url  = URI.join(root, "ruedas/#{id}/export")

    puts "[sync:down] GET #{url}"
    res = Net::HTTP.get_response(url)
    abort "[sync:down] HTTP #{res.code} desde #{url}" unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body)
    puts "[sync:down] descargado #{(res.body.bytesize / 1024.0).round} KB"

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
end
