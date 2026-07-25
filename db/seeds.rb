# Seed — usuario del rol `server` (el equipo que ve todos los pedidos).
#
# El `server` es un concepto propio de la app, no existe en el ERP, así que no
# llega por el sync-down. Se seedea con una identidad sintética (erp_person_id
# reservado) para que el cleanup de usuarios del sync NUNCA lo borre: ese cleanup
# solo elimina capturistas que ya no vienen del ERP, jamás un `server`.
#
# El resto del dataset (rueda, clientes, productos, capturistas) se puebla con
# `rake sync:down` desde rueda-api. En desarrollo, corre el sync contra el ERP
# dev para tener datos reales.

SERVER_ERP_ID = 0 # reservado para la app; el ERP nunca usa 0 como id_persona.

# La contraseña NO tiene default en producción: se exige SEED_SERVER_PASSWORD
# para no dejar una credencial real en el repo. En dev/test hay un default cómodo.
password = ENV["SEED_SERVER_PASSWORD"]
if password.blank?
  abort "Define SEED_SERVER_PASSWORD para sembrar el usuario server." if Rails.env.production?
  password = "rueda2026" # solo desarrollo/test
end

server = User.find_or_initialize_by(erp_person_id: SERVER_ERP_ID)
if server.new_record?
  server.username = ENV.fetch("SEED_SERVER_USERNAME", "servidor")
  server.name     = "Servidor"
  server.role     = "server"
  server.active   = true
  server.password = password
  server.save!
  puts "Seed: usuario server '#{server.username}' creado."
else
  puts "Seed: usuario server '#{server.username}' ya existe (sin cambios)."
end
