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
                            "supplier_skus" => [{ "erp_supplier_id" => 10, "supplier_sku" => "SKU1" }] }]
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
      assert_equal 1, ProductSupplier.count
      assert_equal true, BusinessRound.find_by(erp_round_id: 3).active?

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

    test "guarda: aborta si ya hay pedidos capturados" do
      user   = User.create!(erp_person_id: 1, username: "u", password: "x", role: "capturista")
      round  = BusinessRound.create!(erp_round_id: 1, name: "R")
      client = Client.create!(erp_client_key: "C1", name: "C")
      Order.create!(user: user, business_round: round, client: client, kind: "remission")

      assert_raises(Down::GuardError) { Down.new(export_data).run! }
    end

    test "preserva el usuario server (no viene en el export) y limpia capturistas stale" do
      server = User.create!(erp_person_id: 0, username: "servidor", password: "x", role: "server")
      stale  = User.create!(erp_person_id: 88888, username: "viejo", password: "x", role: "capturista")

      Down.new(export_data).run!

      assert User.exists?(server.id), "el rol server debe sobrevivir al replace"
      assert_not User.exists?(stale.id), "un capturista fuera del export debe eliminarse"
      assert User.exists?(username: "makita1"), "el capturista del export debe existir"
    end

    test "un export sin usuarios NO borra a los capturistas existentes" do
      existente = User.create!(erp_person_id: 90092, username: "makita1", password: "x", role: "capturista")

      result = Down.new(export_data.merge("users" => [])).run!

      assert User.exists?(existente.id),
             "erp_keys vacío no debe disparar el cleanup (where.not(col: []) borraría a todos)"
      assert_empty result.summary[:removed_users]
    end
  end
end
