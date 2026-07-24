# Seed de DESARROLLO — placeholder hasta que exista el sync real (Fase D).
# Crea una rueda activa y un capturista para poder probar login + navegación.
# No usar en producción.
return unless Rails.env.development?

round = BusinessRound.find_or_create_by!(erp_round_id: 3) do |r|
  r.name      = "Rueda de Negocios Oaxaca"
  r.year      = 2026
  r.starts_on = Date.new(2026, 8, 27)
  r.ends_on   = Date.new(2026, 8, 28)
  r.location  = "Hotel Fortín Plaza, Oaxaca, Oax."
  r.active    = true
end

user = User.find_or_initialize_by(username: "capturista")
if user.new_record?
  user.erp_person_id    = 1001
  user.name             = "Capturista"
  user.paternal_surname = "Demo"
  user.active           = true
  user.password         = "rueda2026" # genera el digest bcrypt (solo en el seed)
  user.save!
end

puts "Seed dev listo:"
puts "  rueda: #{round.name} (activa=#{round.active})"
puts "  usuario: #{user.username} / rueda2026"
