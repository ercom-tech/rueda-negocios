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

# Un capturista puede representar a varios proveedores en la rueda.
suppliers = [
  { erp_supplier_id: 501, code: "HITOOL", name: "Hitools" },
  { erp_supplier_id: 502, code: "TRUPER", name: "Truper" }
].each_with_index.map do |attrs, i|
  supplier = Supplier.find_or_create_by!(erp_supplier_id: attrs[:erp_supplier_id]) do |s|
    s.code = attrs[:code]
    s.name = attrs[:name]
  end
  BusinessRoundPerson.find_or_create_by!(business_round: round, user: user, position: i + 1) do |p|
    p.supplier = supplier
  end
  supplier
end

# Catálogo de uso de CFDI (SAT).
{
  "G01" => "Adquisición de mercancías",
  "G03" => "Gastos en general",
  "P01" => "Por definir"
}.each { |code, desc| CfdiUse.find_or_create_by!(code: code) { |c| c.description = desc } }
g01 = CfdiUse.find_by!(code: "G01")

# Vendedor demo (para el catálogo de clientes).
seller = Salesperson.find_or_create_by!(erp_salesperson_id: 900) { |s| s.name = "Juan Pérez López" }

# Cliente con VARIOS datos fiscales y sucursales (caso "elegir").
client_a = Client.find_or_create_by!(erp_client_key: "C0001") do |c|
  c.name            = "Ferretería del Valle"
  c.commercial_name = "Ferrevalle"
  c.email           = "compras@ferrevalle.mx"
  c.approved        = true
  c.salesperson     = seller
end
ClientTaxProfile.find_or_create_by!(client: client_a, rfc: "FVA010101AA1") do |t|
  t.business_name = "FERRETERIA DEL VALLE SA DE CV"; t.default_cfdi_use = g01; t.is_default = true
end
ClientTaxProfile.find_or_create_by!(client: client_a, rfc: "GFV020202BB2") do |t|
  t.business_name = "GRUPO FERREVALLE SA DE CV"; t.default_cfdi_use = g01
end
ClientReceiptProfile.find_or_create_by!(client: client_a, name: "Remisión general") { |r| r.is_default = true }
ClientBranch.find_or_create_by!(client: client_a, name: "Matriz") do |b|
  b.address = "Av. Reforma 100, Oaxaca"; b.is_default = true
end
ClientBranch.find_or_create_by!(client: client_a, name: "Sucursal Norte") { |b| b.address = "Calle 5 Norte 200, Oaxaca" }

# Cliente con UN solo dato (caso "default informativo").
client_b = Client.find_or_create_by!(erp_client_key: "C0002") do |c|
  c.name        = "Construcciones López"
  c.email       = "pagos@construlopez.mx"
  c.approved    = true
  c.salesperson = seller
end
ClientTaxProfile.find_or_create_by!(client: client_b, rfc: "CLO030303CC3") do |t|
  t.business_name = "CONSTRUCCIONES LOPEZ SA DE CV"; t.default_cfdi_use = g01; t.is_default = true
end
ClientBranch.find_or_create_by!(client: client_b, name: "Única") do |b|
  b.address = "Blvd. Sur 50, Oaxaca"; b.is_default = true
end

puts "Seed dev listo:"
puts "  rueda: #{round.name} (activa=#{round.active})"
puts "  usuario: #{user.username} / rueda2026"
puts "  proveedores: #{suppliers.map(&:name).join(", ")}"
puts "  clientes: #{Client.pluck(:erp_client_key, :name).map { |k, n| "#{k} #{n}" }.join(" | ")}"
