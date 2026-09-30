namespace :evidence do
  # Reconstruye la evidencia de los pedidos de una rueda desde un RESPALDO de
  # la laptop (2026-09-30). Para las ruedas que se transmitieron antes de que
  # existiera `vta_pedido_rueda` (Oaxaca): sus pedidos ya están en el ERP, pero
  # sin la copia tal como se capturaron.
  #
  # Se corre sobre el respaldo RESTAURADO, nunca sobre la base de la laptop en
  # uso, y el archivo que produce lo importa `rueda-api` (`rake
  # evidence:import`), que la guarda con origen `respaldo`: no es lo mismo que
  # una recepción, y la evidencia lo dice.
  #
  # El paquete es el de `Sync::Up#build_payload`, el mismo que manda la
  # transmisión: así la evidencia reconstruida y la recibida no pueden diferir
  # en forma.
  #
  #   DB_NAME=rueda_restore bin/rails evidence:export OUT=evidencia-oaxaca.json
  desc "Exporta los pedidos transmitidos de un respaldo como evidencia para el ERP. ENV: OUT"
  task export: :environment do
    out = ENV.fetch("OUT") { abort "Falta OUT (archivo JSON de salida)" }
    orders = Order.transmitted.includes(:user, :business_round, :client, order_items: %i[product promotion promotion_tier supplier brand])
                  .order(:id)
    abort "[evidence:export] no hay pedidos transmitidos en #{ActiveRecord::Base.connection.current_database}" if orders.none?

    builder = Sync::Up.new("http://no-se-usa")
    records = orders.map do |order|
      claves = Array(order.erp_folios).presence || [ order.erp_folio ].compact
      { payload: builder.build_payload(order), claves: claves }
    end

    File.write(out, JSON.pretty_generate(records))
    sin_folio = records.count { |record| record[:claves].empty? }
    puts "[evidence:export] #{records.size} pedidos de #{ActiveRecord::Base.connection.current_database} → #{out}"
    puts "[evidence:export] AVISO: #{sin_folio} sin folio del ERP" if sin_folio.positive?
  end
end
