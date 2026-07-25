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

# Marcas y productos demo (para la búsqueda del detalle del pedido).
stanley = Brand.find_or_create_by!(erp_brand_id: 10) { |b| b.name = "Stanley"; b.code = "ST" }
truper  = Brand.find_or_create_by!(erp_brand_id: 11) { |b| b.name = "Truper"; b.code = "TR" }
hitools = Supplier.find_by(erp_supplier_id: 501)

[
  { id: 91384,  desc: "Rotomartillo Stanley", part: "45670", unit: "PZA", model: "STDR5010", price: 1534.00, brand: stanley },
  { id: 98821,  desc: "Martillo",             part: "54321", unit: "PZA", model: "MG-1000",  price: 120.00,  brand: truper },
  { id: 18831,  desc: "Clavo 2\"",            part: "76543", unit: "KG",  model: "CL-2",     price: 40.00,   brand: truper },
  { id: 348282, desc: "Pala",                 part: "53223", unit: "PZA", model: "PT-16",    price: 300.00,  brand: truper },
  { id: 823272, desc: "Broca 3/4",            part: "87654", unit: "PZA", model: "BR-34",    price: 30.00,   brand: stanley }
].each do |a|
  product = Product.find_or_create_by!(erp_product_id: a[:id]) do |p|
    p.description = a[:desc]; p.part_number = a[:part]; p.unit = a[:unit]
    p.model = a[:model]; p.brand = a[:brand]; p.stock = 100
  end
  Price.find_or_create_by!(product: product) do |pr|
    pr.public_price = a[:price]; pr.wholesale_price = (a[:price] * 0.9).round(2); pr.tax_rate = 16
  end
  ProductSupplier.find_or_create_by!(product: product, supplier: hitools) { |ps| ps.supplier_sku = "HIT-#{a[:id]}" } if hitools
end

# Usuarios para validar el reporte por rol.
servidor = User.find_or_initialize_by(username: "servidor")
if servidor.new_record?
  servidor.attributes = { erp_person_id: 1002, name: "Servidor", role: "server", active: true }
  servidor.password = "rueda2026"
  servidor.save!
end

cap2 = User.find_or_initialize_by(username: "capturista2")
if cap2.new_record?
  cap2.attributes = { erp_person_id: 1003, name: "Ana", paternal_surname: "Ramírez", role: "capturista", active: true }
  cap2.password = "rueda2026"
  cap2.save!
end

# Pedido capturado por capturista2 (el capturista original NO lo ve; el servidor SÍ).
if cap2.orders.none?
  o = Order.create!(
    user: cap2, business_round: round, client: client_b, kind: "invoice",
    client_tax_profile: client_b.tax_profiles.first, cfdi_use: g01,
    client_branch: client_b.branches.first, status: "submitted"
  )
  o.update!(local_folio: "RN-#{o.id.to_s.rjust(6, '0')}")
  martillo = Product.find_by(erp_product_id: 98821)
  o.order_items.create!(martillo.to_order_item_attributes.merge(position: 1, quantity: 5, discount_percent: 0))
end

puts "Seed dev listo:"
puts "  rueda: #{round.name} (activa=#{round.active})"
puts "  usuario: #{user.username} / rueda2026"
puts "  proveedores: #{suppliers.map(&:name).join(", ")}"
puts "  clientes: #{Client.pluck(:erp_client_key, :name).map { |k, n| "#{k} #{n}" }.join(" | ")}"
