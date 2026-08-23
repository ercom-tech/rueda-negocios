namespace :sync do
  # Registra la corrida igual que los jobs del panel. Sin esto, un sync desde la
  # terminal era INVISIBLE para el panel: `SyncRun.running.exists?` daba falso,
  # así que "Cerrar rueda" quedaba habilitado y su `destroy_all` podía correr
  # encima del `find_each` del rake — el pedido entra al ERP y el `update!` del
  # folio escribe sobre una fila ya borrada, sin excepción (Rails no falla
  # cuando el UPDATE afecta 0 filas). El folio se perdía en silencio.
  #
  # Valida la condición previa y abre la corrida. La guarda va ANTES de crear
  # el SyncRun, igual que en el panel: una condición que nunca llegó a
  # intentarse no debe quedar registrada como corrida fallida (los servicios la
  # repiten adentro como red para las carreras).
  #
  # Lambda y no `def`: dentro de un .rake, `def` define el método en Object.
  start_run = lambda do |kind, service|
    begin
      service.guard!
    rescue Sync::Down::GuardError, Sync::Up::GuardError => e
      abort "[sync:#{kind}] abortado: #{e.message}"
    end

    run = SyncRun.start(kind)
    next run if run

    abort "[sync:#{kind}] ya hay una corrida en curso (obtener información o " \
          "transmitir pedidos). Espera a que termine."
  end

  desc "Descarga el dataset de la rueda desde rueda-api y puebla el Postgres local (idempotente). ENV: RUEDA_API_URL, RUEDA_ID"
  task down: :environment do
    base = ENV.fetch("RUEDA_API_URL") { abort "Falta RUEDA_API_URL (base de rueda-api, p.ej. http://localhost:4568)" }
    id   = ENV.fetch("RUEDA_ID")      { abort "Falta RUEDA_ID (id_rueda del ERP a descargar)" }

    run = start_run.call("down", Sync::Down)

    begin
      puts "[sync:down] descargando rueda #{id} desde #{base}"
      data = Sync::ApiClient.new(base).fetch_export(id)
      puts "[sync:down] descargado (#{data['products']&.size || 0} productos)"

      result = ActiveRecord::Base.transaction { Sync::Down.new(data).run! }
      run.finish!(status: :completed, summary: result.summary)
    rescue Sync::ApiClient::Error, Sync::Down::GuardError => e
      run.finish!(status: :failed, message: e.message)
      abort "[sync:down] abortado: #{e.message}"
    rescue StandardError => e
      run.finish!(status: :failed, message: e.message)
      raise
    ensure
      # Ctrl-C, kill o cualquier excepción fuera de StandardError no pasan
      # por los rescue de arriba: sin este cierre la corrida quedaba
      # `running` para siempre — captura pausada, panel girando y "Cerrar
      # rueda" bloqueado hasta reiniciar el servidor (5ª auditoría).
      run.finish_interrupted! if run.running?
    end

    s = result.summary

    puts "[sync:down] entidades:"
    s[:entities].each { |table, n| puts format("  %-24s %d", table, n) }
    puts "[sync:down] usuarios omitidos (sin credencial): #{s[:skipped_users].size} #{s[:skipped_users].inspect if s[:skipped_users].any?}"
    puts "[sync:down] capturistas eliminados (fuera de la rueda): #{s[:removed_users].size} #{s[:removed_users].inspect if s[:removed_users].any?}"
    puts "[sync:down] capturistas con asignación incompleta (solo fuera de catálogo): #{s[:skipped_people].size} #{s[:skipped_people].inspect if s[:skipped_people].any?}"
    puts "[sync:down] SKUs omitidos (proveedor fuera de la rueda): #{s[:skipped_skus]}"
    puts "[sync:down] productos de promoción que no llegaron al catálogo: #{s[:skipped_promotion_products]}"
    puts "[sync:down] productos en más de una promoción (solo se ofrece una): #{s[:shared_promotion_products].size} #{s[:shared_promotion_products].inspect if s[:shared_promotion_products].any?}"
    puts "[sync:down] pedidos locales purgados por el reemplazo: #{s[:purged_orders]}"
    puts "[sync:down] listo. Si el panel del servidor está abierto en un navegador, recárgalo para ver esta corrida."
  end

  desc "Transmite los pedidos capturados al ERP vía rueda-api (idempotente). ENV: RUEDA_API_URL"
  task up: :environment do
    base = ENV.fetch("RUEDA_API_URL") { abort "Falta RUEDA_API_URL (base de rueda-api, p.ej. http://localhost:4568)" }

    pending = Order.captured.where(erp_folio: nil).count
    puts "[sync:up] pedidos por transmitir: #{pending}"

    run = start_run.call("up", Sync::Up)

    r = begin
      result = Sync::Up.new(base).run!
      run.finish!(status: (result[:failed].any? ? :failed : :completed), summary: result)
      result
    rescue Sync::Up::GuardError => e
      run.finish!(status: :failed, message: e.message)
      abort "[sync:up] abortado: #{e.message}"
    rescue StandardError => e
      run.finish!(status: :failed, message: e.message)
      raise
    ensure
      # Mismo cierre que sync:down: una muerte por señal no pasa por los
      # rescue y dejaba la corrida `running` para siempre.
      run.finish_interrupted! if run.running?
    end

    r[:transmitted].each { |t| puts "  ✓ #{t[:local]} → folio ERP #{t[:erp]}" }
    r[:failed].each      { |f| puts "  ✗ #{f[:local]} (HTTP #{f[:status]}): #{f[:error]}" }
    puts "[sync:up] transmitidos: #{r[:transmitted].size}, fallidos: #{r[:failed].size}"
    abort "[sync:up] hubo pedidos fallidos." if r[:failed].any?
    puts "[sync:up] listo. Si el panel del servidor está abierto en un navegador, recárgalo para ver esta corrida."
  end
end
