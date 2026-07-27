require "test_helper"

module Sync
  class DownTest < ActiveSupport::TestCase
    # Dataset de export mínimo pero completo (una de cada entidad).
    def export_data
      digest = BCrypt::Password.create("secreto").to_s
      {
        "round"       => { "erp_round_id" => 3, "name" => "Oaxaca", "year" => 2026,
                           "starts_on" => "2026-08-27", "ends_on" => "2026-08-28", "location" => "Oaxaca" },
        "cfdi_uses"   => [{ "code" => "G01", "description" => "Adquisición de mercancías" }],
        "users"       => [{ "erp_person_id" => 90092, "username" => "makita1", "password_hash" => digest,
                            "name" => "PROVEEDOR", "paternal_surname" => nil, "maternal_surname" => nil,
                            "rfc" => nil, "prefijo" => "1A" }],
        "salespeople" => [{ "erp_salesperson_id" => 168, "name" => "Omar", "erp_person_id" => nil }],
        "suppliers"   => [{ "erp_supplier_id" => 10, "code" => "S1", "name" => "Prov", "commercial_name" => nil }],
        "brands"      => [{ "erp_brand_id" => 1, "name" => "Stanley", "code" => "ST" }],
        "clients"     => [{ "erp_client_key" => "ABAISM", "name" => "Ismael", "commercial_name" => "Ferretería Inti",
                            "email" => nil, "erp_salesperson_id" => 168,
                            "tax_profiles"    => [{ "rfc" => "XAXX010101000", "business_name" => "RS", "default_cfdi_use" => "G01" }],
                            "receipt_profiles" => [],
                            "branches"        => [{ "consecutive" => 1, "name" => "Matriz", "address" => "Calle 1", "is_default" => true }] }],
        "products"    => [{ "erp_product_id" => 3, "description" => "Rotomartillo", "part_number" => nil, "model" => nil,
                            "erp_brand_id" => 1, "stock" => "0.0", "unit" => "PZA",
                            "public_price" => "471.08", "wholesale_price" => "407.82", "tax_rate" => "16.0", "max_discount" => "0.0",
                            "supplier_ids" => [10, 99],
                            "supplier_skus" => [{ "erp_supplier_id" => 10, "supplier_sku" => "SKU1" }] }],
        "people"      => [{ "erp_person_id" => 90092, "position" => 1,
                            "erp_supplier_id" => 10, "erp_brand_id" => nil }]
      }
    end

    test "replace: deja la BD igual al export" do
      result = Down.new(export_data).run!

      assert_equal 1, CfdiUse.count
      assert_equal 1, Brand.count
      assert_equal 1, Supplier.count
      assert_equal 1, Salesperson.count
      assert_equal 1, Client.count
      assert_equal 1, Product.count
      assert_equal 1, Price.count
      assert_equal 1, ProductSupplier.count # supplier_ids 99 no es de la rueda → omitido
      assert_equal true, BusinessRound.find_by(erp_round_id: 3).active?

      membership = BusinessRoundPerson.sole
      assert_equal 90092, membership.user.erp_person_id
      assert_equal 10, membership.supplier.erp_supplier_id
      assert_nil membership.brand_id

      user = User.find_by(erp_person_id: 90092)
      assert_equal "makita1", user.username
      assert_equal "1A", user.prefix
      assert user.authenticate("secreto"), "el digest bcrypt del ERP debe validar"

      client = Client.find_by(erp_client_key: "ABAISM")
      assert_equal "Ferretería Inti", client.commercial_name
      assert_equal 168, client.salesperson.erp_salesperson_id
      assert_equal 1, client.tax_profiles.count
      assert_equal 1, client.branches.count

      assert_equal({ "products" => 1, "clients" => 1, "users" => 1 },
                   result.summary[:entities].slice("products", "clients", "users"))
    end

    test "guarda: aborta solo con pedidos capturados sin transmitir" do
      user   = User.create!(erp_person_id: 1, username: "u", password: "x", role: "capturista")
      round  = BusinessRound.create!(erp_round_id: 1, name: "R")
      client = Client.create!(erp_client_key: "C1", name: "C")
      Order.create!(user: user, business_round: round, client: client,
                    kind: "remission", status: "captured", local_folio: "RN-000001")

      error = assert_raises(Down::GuardError) { Down.new(export_data).run! }
      assert_match(/sin transmitir/, error.message)
    end

    test "borradores y transmitidos NO bloquean: se purgan y el refresh procede" do
      user   = User.create!(erp_person_id: 1, username: "u", password: "x", role: "capturista")
      round  = BusinessRound.create!(erp_round_id: 1, name: "R")
      client = Client.create!(erp_client_key: "C1", name: "C")
      Order.create!(user: user, business_round: round, client: client, kind: "remission")
      Order.create!(user: user, business_round: round, client: client, kind: "remission",
                    status: "transmitted", erp_folio: "1A0001", local_folio: "RN-000002")

      result = Down.new(export_data).run!

      assert_equal 2, result.summary[:purged_orders]
      assert_equal 0, Order.count, "borradores y transmitidos purgados"
      assert_equal 1, Product.count, "el replace procede con normalidad"
    end

    test "preserva el usuario server (no viene en el export) y limpia capturistas stale" do
      server = User.create!(erp_person_id: 0, username: "servidor", password: "x", role: "server")
      stale  = User.create!(erp_person_id: 88888, username: "viejo", password: "x", role: "capturista")

      Down.new(export_data).run!

      assert User.exists?(server.id), "el rol server debe sobrevivir al replace"
      assert_not User.exists?(stale.id), "un capturista fuera del export debe eliminarse"
      assert User.exists?(username: "makita1"), "el capturista del export debe existir"
    end

    test "un export sin usuarios SÍ limpia a los capturistas (replace pleno) pero preserva al server" do
      # Decisión del usuario: si el ERP no asignó usuarios a la rueda es
      # problema operativo, no del sitio — los capturistas quedan idénticos
      # al export (cero). El server (seedeado) es infraestructura y sobrevive.
      server     = User.create!(erp_person_id: 0, username: "servidor", password: "x", role: "server")
      capturista = User.create!(erp_person_id: 90092, username: "makita1", password: "x", role: "capturista")

      result = Down.new(export_data.merge("users" => [])).run!

      assert_not User.exists?(capturista.id), "el replace deja los capturistas idénticos al export"
      assert User.exists?(server.id), "el server seedeado debe sobrevivir siempre"
      assert_equal ["makita1"], result.summary[:removed_users]
      assert_equal 1, result.summary[:skipped_people],
                   "la membresía de un usuario inexistente se omite y se reporta"
    end
  end
end
