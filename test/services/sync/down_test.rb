require "test_helper"

module Sync
  class DownTest < ActiveSupport::TestCase
    # Dataset de export mínimo pero completo (una de cada entidad).
    def export_data
      digest = BCrypt::Password.create("secreto").to_s
      {
        "round"       => { "erp_round_id" => 3, "name" => "Oaxaca", "year" => 2026,
                           "starts_on" => "2026-08-27", "ends_on" => "2026-08-28", "location" => "Oaxaca" },
        "cfdi_uses"   => [ { "code" => "G01", "description" => "Adquisición de mercancías" } ],
        "users"       => [ { "erp_person_id" => 90092, "username" => "makita1", "password_hash" => digest,
                            "name" => "PROVEEDOR", "paternal_surname" => nil, "maternal_surname" => nil,
                            "rfc" => nil, "prefijo" => "1A" } ],
        "salespeople" => [ { "erp_salesperson_id" => 168, "name" => "Omar", "erp_person_id" => nil } ],
        "suppliers"   => [ { "erp_supplier_id" => 10, "code" => "S1", "name" => "Prov", "commercial_name" => nil } ],
        "brands"      => [ { "erp_brand_id" => 1, "name" => "Stanley", "code" => "ST" } ],
        "clients"     => [ { "erp_client_key" => "ABAISM", "name" => "Ismael", "commercial_name" => "Ferretería Inti",
                            "email" => nil, "erp_salesperson_id" => 168,
                            "tax_profiles"    => [ { "rfc" => "XAXX010101000", "business_name" => "RS", "default_cfdi_use" => "G01" } ],
                            "receipt_profiles" => [],
                            "branches"        => [ { "consecutive" => 1, "name" => "Matriz", "address" => "Calle 1", "is_default" => true } ] } ],
        "products"    => [ { "erp_product_id" => 3, "description" => "Rotomartillo", "part_number" => nil, "model" => nil,
                            "erp_brand_id" => 1, "stock" => "0.0", "unit" => "PZA",
                            "public_price" => "471.08", "wholesale_price" => "407.82",
                            "credit_wholesale_price" => "429.44", "tax_rate" => "16.0", "max_discount" => "0.0",
                            "min_sale_quantity" => "6",
                            "supplier_ids" => [ 10, 99 ],
                            "supplier_skus" => [ { "erp_supplier_id" => 10, "supplier_sku" => "SKU1" } ] } ],
        "people"      => [ { "erp_person_id" => 90092, "position" => 1,
                            "erp_supplier_id" => 10, "erp_brand_id" => nil } ],
        "divide_amounts" => [ { "consecutive" => 1, "amount" => "0" },
                             { "consecutive" => 2, "amount" => "2000" } ]
      }
    end

    test "replace: deja la BD igual al export" do
      result = Down.new(export_data).run!

      assert_equal 1, CfdiUse.count
      assert_equal 2, DivideAmount.count
      assert_equal [ "No dividir", "$2,000" ], DivideAmount.ordered.map(&:label)
      assert_equal 1, Brand.count
      assert_equal 1, Supplier.count
      assert_equal 1, Salesperson.count
      assert_equal 1, Client.count
      assert_equal 1, Product.count
      assert_equal 6, Product.sole.min_sale_quantity, "el empaque mínimo debe sincronizarse"
      assert_equal 1, Price.count
      assert_equal 429.44, Price.sole.credit_wholesale_price,
                   "el precio crédito mayoreo (el que cobra la rueda) debe sincronizarse"
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

    # El buscador promete el 999999; si el dataset no lo trajo (servidor
    # viejo o baja en el ERP), el summary lo delata para que el panel avise
    # en vez de dejar la promesa en bucle (6ª auditoría).
    test "el summary delata cuando el dataset no trae el genérico" do
      assert Down.new(export_data).run!.summary[:missing_generic],
             "el export mínimo no trae el 999999"

      with_generic = export_data
      with_generic["products"] << { "erp_product_id" => Product::GENERIC_ERP_ID,
                                    "description" => "AJUSTE DE MERCANCIA", "part_number" => nil,
                                    "model" => nil, "erp_brand_id" => nil, "stock" => "0", "unit" => "PZA",
                                    "public_price" => "5.25", "wholesale_price" => "4.54",
                                    "credit_wholesale_price" => "4.78", "tax_rate" => "16.0",
                                    "max_discount" => "9.0", "min_sale_quantity" => nil,
                                    "supplier_ids" => [], "supplier_skus" => [] }
      assert_not Down.new(with_generic).run!.summary[:missing_generic]
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

    # Cambio de criterio (2026-08-10): un borrador SÍ bloquea. El replace lo
    # purga, así que descargar con borradores vivos borraba en silencio un
    # pedido en captura. Misma regla que el sync-up (Sync::Guards).
    test "guarda: un borrador bloquea el refresh (el replace lo borraría)" do
      user   = User.create!(erp_person_id: 1, username: "u", password: "x", role: "capturista")
      round  = BusinessRound.create!(erp_round_id: 1, name: "R")
      client = Client.create!(erp_client_key: "C1", name: "C")
      Order.create!(user: user, business_round: round, client: client, kind: "remission")

      error = assert_raises(Down::GuardError) { Down.new(export_data).run! }
      assert_match(/en borrador/, error.message)
      assert_equal 1, Order.count, "no debe purgar nada si abortó"
    end

    test "los transmitidos NO bloquean: se purgan y el refresh procede" do
      user   = User.create!(erp_person_id: 1, username: "u", password: "x", role: "capturista")
      round  = BusinessRound.create!(erp_round_id: 1, name: "R")
      client = Client.create!(erp_client_key: "C1", name: "C")
      Order.create!(user: user, business_round: round, client: client, kind: "remission",
                    status: "transmitted", erp_folio: "1A0001", local_folio: "RN-000002")

      result = Down.new(export_data).run!

      assert_equal 1, result.summary[:purged_orders]
      assert_equal 0, Order.count, "los transmitidos (ya en el ERP) se purgan"
      assert_equal 1, Product.count, "el replace procede con normalidad"
    end

    test "un pedido finalizado en plena obtención deshace el reemplazo completo" do
      # La carrera: un POST de "Finalizar" pasó la pausa antes del alta de la
      # corrida y su commit aterriza entre la guarda y el purge. Con
      # `Order.destroy_all` esa venta se perdía en silencio; el borrado
      # acotado + la re-guarda dentro de la transacción lo deshacen todo —
      # espejo de la prueba equivalente de CloseRound. (5ª auditoría.)
      user   = User.create!(erp_person_id: 1, username: "u", password: "x", role: "capturista")
      round  = BusinessRound.create!(erp_round_id: 1, name: "R")
      client = Client.create!(erp_client_key: "C1", name: "C")
      Order.create!(user: user, business_round: round, client: client, kind: "remission",
                    status: "transmitted", erp_folio: "1A0001", local_folio: "RN-000002")
      late_order = Order.create!(user: user, business_round: round, client: client, kind: "remission",
                               status: "transmitted", erp_folio: "1A0002", local_folio: "RN-000003")

      # Se engancha al primer `Order.transmitted` (el conteo del purge), que
      # ocurre después de la guarda. Módulo antepuesto que se desactiva solo:
      # quitar el scope del singleton lo borraría para el resto del proceso.
      colado = false
      Order.singleton_class.prepend(Module.new do
        define_method(:transmitted) do
          unless colado
            colado = true
            late_order.update_columns(status: "captured", erp_folio: nil)
          end
          super()
        end
      end)

      # La transacción es la del job/rake: el servicio confía en ella.
      assert_raises(Down::GuardError) do
        ActiveRecord::Base.transaction { Down.new(export_data).run! }
      end

      # El rollback también deshace el flip simulado (aquí corre en la misma
      # conexión; en la carrera real es otra), así que lo comprobable es lo
      # esencial: la re-guarda abortó y ningún pedido se perdió.
      assert_equal 2, Order.count, "no se pierde ningún pedido"
      assert Order.exists?(late_order.id), "la venta colada sobrevive"
    end

    test "preserva el usuario server (no viene en el export) y limpia capturistas stale" do
      server = User.create!(erp_person_id: 0, username: "servidor", password: "x", role: "server")
      stale  = User.create!(erp_person_id: 88888, username: "viejo", password: "x", role: "capturista")

      Down.new(export_data).run!

      assert User.exists?(server.id), "el rol server debe sobrevivir al replace"
      assert_not User.exists?(stale.id), "un capturista fuera del export debe eliminarse"
      assert User.exists?(username: "makita1"), "el capturista del export debe existir"
    end

    test "membresía solo-marca (proveedor 0 → nil en el export) se importa" do
      people = [
        { "erp_person_id" => 90092, "position" => 1, "erp_supplier_id" => 10, "erp_brand_id" => nil },
        { "erp_person_id" => 90092, "position" => 2, "erp_supplier_id" => nil, "erp_brand_id" => 1 }
      ]

      Down.new(export_data.merge("people" => people)).run!

      memberships = BusinessRoundPerson.order(:position).to_a
      assert_equal 2, memberships.size
      brand_only = memberships.last
      assert_nil brand_only.supplier_id
      assert_equal 1, brand_only.brand.erp_brand_id
    end

    test "capturista con contraseña ilegible se omite sin duplicar el diagnóstico" do
      # Su membresía cae con él: si además se contara en `skipped_people`, el
      # panel diría "sin proveedor ni marca — pide que lo asignen en el ERP",
      # mandando a corregir lo que no está roto. El aviso correcto es el de la
      # credencial, una sola vez. (5ª auditoría.)
      users = [ { "erp_person_id" => 90092, "username" => "makita1",
                  "password_hash" => "{SHA}abcdef", "name" => "M", "paternal_surname" => "P",
                  "maternal_surname" => nil, "rfc" => nil, "prefijo" => "1A" } ]

      result = Down.new(export_data.merge("users" => users)).run!

      assert_equal [ "makita1" ], result.summary[:skipped_users]
      assert_not User.exists?(username: "makita1")
      assert_empty result.summary[:skipped_people],
                   "la membresía del omitido por credencial no se reporta aparte"
      assert_equal 0, BusinessRoundPerson.count
    end

    test "membresía con referencia rota o sin proveedor ni marca se omite y se reporta" do
      people = [
        { "erp_person_id" => 90092, "position" => 1, "erp_supplier_id" => nil, "erp_brand_id" => 999 },
        { "erp_person_id" => 90092, "position" => 2, "erp_supplier_id" => nil, "erp_brand_id" => nil }
      ]

      result = Down.new(export_data.merge("people" => people)).run!

      assert_equal 0, BusinessRoundPerson.count
      assert_equal [ "makita1" ], result.summary[:skipped_people], "por persona, no por renglón (2 membresías rotas = 1 capturista)"
    end

    test "un export sin usuarios SÍ limpia a los capturistas (replace pleno) pero preserva al server" do
      # Decisión del usuario: si el ERP no asignó usuarios a la rueda es
      # problema operativo, no del sitio — los capturistas quedan idénticos
      # al export (cero). El server (seedeado) es infraestructura y sobrevive.
      server     = User.create!(erp_person_id: 0, username: "servidor", password: "x", role: "server")
      user = User.create!(erp_person_id: 90092, username: "makita1", password: "x", role: "capturista")

      result = Down.new(export_data.merge("users" => [])).run!

      assert_not User.exists?(user.id), "el replace deja los capturistas idénticos al export"
      assert User.exists?(server.id), "el server seedeado debe sobrevivir siempre"
      assert_equal [ "makita1" ], result.summary[:removed_users]
      assert_equal 1, result.summary[:skipped_people].size,
                   "la membresía de un usuario inexistente se omite y se reporta"
    end
  end
end
