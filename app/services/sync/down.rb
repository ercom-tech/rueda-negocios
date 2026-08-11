module Sync
  # Puebla el Postgres local con el dataset de una rueda (respuesta de
  # `GET /ruedas/:id/export` de rueda-api). Es un **refresh pre-evento**:
  # deja el catálogo local idéntico al export (replace), no un merge.
  #
  # Guarda: aborta solo si hay pedidos capturados SIN transmitir (ventas que
  # se perderían). Los borradores (capturas incompletas) y los transmitidos
  # (ya viven en el ERP) no bloquean: se purgan antes del replace — así el
  # refresh entre días del evento es transmitir → obtener información.
  #
  # Usuarios: mismo REPLACE que las demás tablas — los capturistas quedan
  # idénticos al export (upsert por `erp_person_id` + limpieza de los que no
  # vienen, incluso si el export trae cero: eso es problema operativo del ERP).
  # Única excepción: el usuario `server` (seedeado) sobrevive siempre — es
  # infraestructura de la app, no dato del ERP.
  #
  # Alcance: las 9 entidades del export, incluida la membresía
  # capturista↔proveedor/marca (`people` → business_round_people), que define
  # el universo de productos de cada capturista. Las demás tablas de membresía
  # (brands_suppliers, business_round_*) siguen sin venir en el export; solo se
  # vacían para que el replace no choque con FKs.
  class Down
    # Se levanta cuando la guarda impide correr el sync (hay pedidos).
    class GuardError < StandardError; end

    # El replace borra todos los pedidos locales: los borradores (en captura) y
    # los finalizados sin transmitir (ventas reales que aún no llegan al ERP)
    # se perderían. Método de clase (no usa estado del objeto) para que el
    # controlador pueda preguntarlo ANTES de crear el SyncRun — una condición
    # previa no debe quedar registrada como una corrida fallida; `run!` lo
    # repite para cubrir `rake sync:down` y el job.
    def self.guard!
      Guards.no_local_orders!(GuardError, "al obtener la información")
    end

    def initialize(data)
      @data = data
      @stats = {}
      @skipped_users = []
      @removed_users = []
      @skipped_skus = 0
      @skipped_people = 0
      @purged_orders = 0
    end

    def run!
      self.class.guard!
      purge_local_orders!
      clear_catalog!
      import_cfdi_uses
      import_divide_amounts
      import_brands
      import_suppliers
      import_salespeople
      import_round
      import_users
      import_clients
      import_products
      import_people
      self
    end

    def summary
      { entities: @stats, skipped_users: @skipped_users,
        removed_users: @removed_users, skipped_skus: @skipped_skus,
        skipped_people: @skipped_people, purged_orders: @purged_orders }
    end

    private

    # Borradores y transmitidos no bloquean el refresh, pero sus FKs chocarían
    # con el replace del catálogo: se purgan (y se reporta cuántos).
    def purge_local_orders!
      @purged_orders = Order.count
      Order.destroy_all if @purged_orders.positive?
    end

    # Borra el catálogo (hijos → padres) para repoblarlo idéntico al export.
    # Las tablas de membresía se vacían primero: cuelgan de brands/suppliers/
    # salespeople/clients/rounds y bloquearían el delete por FK.
    def clear_catalog!
      [ BusinessRoundPerson, BusinessRoundClient ].each(&:delete_all)
      exec_delete("business_round_brands")
      exec_delete("business_round_suppliers")
      exec_delete("business_round_salespeople")
      exec_delete("brands_suppliers")

      [ Price, ProductSupplier, Product,
       ClientTaxProfile, ClientReceiptProfile, ClientBranch, Client,
       Salesperson, Supplier, Brand, CfdiUse, DivideAmount, BusinessRound ].each(&:delete_all)
    end

    def exec_delete(table)
      ActiveRecord::Base.connection.execute("DELETE FROM #{table}")
    end

    # --- Catálogos base (sin dependencias) --------------------------------

    def import_cfdi_uses
      rows = @data["cfdi_uses"].map { |c| { code: c["code"], description: c["description"] } }
      insert CfdiUse, rows
    end

    # Montos de división de facturas (combo del paso 1). Array() por
    # compatibilidad con exports viejos sin la llave.
    def import_divide_amounts
      rows = Array(@data["divide_amounts"]).map do |d|
        { erp_consecutive: d["consecutive"], amount: d["amount"] }
      end
      insert DivideAmount, rows
    end

    def import_brands
      rows = @data["brands"].map do |b|
        { erp_brand_id: b["erp_brand_id"], name: b["name"], code: b["code"] }
      end
      insert Brand, rows
    end

    def import_suppliers
      rows = @data["suppliers"].map do |s|
        { erp_supplier_id: s["erp_supplier_id"], code: s["code"],
          name: s["name"], commercial_name: s["commercial_name"] }
      end
      insert Supplier, rows
    end

    def import_salespeople
      rows = @data["salespeople"].map do |v|
        { erp_salesperson_id: v["erp_salesperson_id"], name: v["name"],
          erp_person_id: v["erp_person_id"] }
      end
      insert Salesperson, rows
    end

    # --- Rueda: la importada queda como la activa -------------------------

    def import_round
      r = @data["round"]
      row = { erp_round_id: r["erp_round_id"], name: r["name"], year: r["year"],
              starts_on: r["starts_on"], ends_on: r["ends_on"],
              location: r["location"], active: true }
      insert BusinessRound, [ row ]
    end

    # --- Usuarios (capturistas): merge + cleanup, preservando servers -----

    # `erp_person_id = 0` está RESERVADO para la cuenta `server` que se seedea
    # (es infraestructura de la app, no una persona del ERP). Si el export
    # trajera una persona con ese id, el upsert le sobrescribiría usuario y
    # contraseña conservando el rol: esa persona se quedaría con la cuenta que
    # ve todos los pedidos y opera el sync, y el operador real perdería el
    # acceso sin ningún aviso.
    SERVER_ERP_ID = 0

    def import_users
      importable = @data["users"].reject { |u| u["erp_person_id"].to_i == SERVER_ERP_ID }
      erp_keys   = importable.map { |u| u["erp_person_id"] }.compact

      rows = []
      importable.each do |u|
        # No solo el vacío: un digest que no es bcrypt tampoco sirve para
        # entrar, y además tumbaba el login con un error del sistema. Se omite
        # aquí, donde el operador puede verlo en la lista de omitidos, en vez de
        # descubrirlo cuando el capturista no logra entrar en pleno evento.
        unless u["password_hash"].to_s.start_with?("$2")
          @skipped_users << (u["username"] || u["erp_person_id"])
          next
        end
        rows << { erp_person_id: u["erp_person_id"], username: u["username"],
                  password_digest: u["password_hash"], name: u["name"],
                  paternal_surname: u["paternal_surname"],
                  maternal_surname: u["maternal_surname"], rfc: u["rfc"],
                  prefix: u["prefijo"] }
      end
      # Upsert por erp_person_id sin tocar `role` (columna ausente en las filas).
      User.upsert_all(rows, unique_by: :erp_person_id, record_timestamps: true) if rows.any?

      # Cleanup: REPLACE pleno, igual que el resto de las tablas — los
      # capturistas quedan idénticos al export. Si el export viene sin
      # usuarios, se limpian TODOS (decisión del usuario: asignar usuarios a
      # la rueda es responsabilidad operativa del ERP, no del sitio). El único
      # que sobrevive siempre es el `server`: es infraestructura seedeada de
      # la app (opera el panel), no dato del ERP.
      stale = erp_keys.any? ? User.capturista.where.not(erp_person_id: erp_keys)
                            : User.capturista.all
      @removed_users = stale.pluck(:username)
      stale.delete_all
      @stats["users"] = rows.size
    end

    # --- Clientes + perfiles fiscales / remisión / sucursal ---------------

    def import_clients
      sp_by_erp = Salesperson.pluck(:erp_salesperson_id, :id).to_h

      rows = @data["clients"].map do |c|
        { erp_client_key: c["erp_client_key"], name: c["name"],
          commercial_name: c["commercial_name"], email: c["email"],
          salesperson_id: sp_by_erp[c["erp_salesperson_id"]] }
      end
      insert Client, rows

      client_by_key = Client.pluck(:erp_client_key, :id).to_h
      cfdi_by_code  = CfdiUse.pluck(:code, :id).to_h

      tax_rows, receipt_rows, branch_rows = [], [], []
      @data["clients"].each do |c|
        cid = client_by_key[c["erp_client_key"]]
        next unless cid

        (c["tax_profiles"] || []).each_with_index do |t, i|
          tax_rows << { client_id: cid, rfc: t["rfc"], business_name: t["business_name"],
                        default_cfdi_use_id: cfdi_by_code[t["default_cfdi_use"]],
                        is_default: i.zero? }
        end
        (c["receipt_profiles"] || []).each_with_index do |r, i|
          receipt_rows << { client_id: cid, erp_receipt_profile_id: r["consecutive"],
                            name: r["name"], is_default: i.zero? }
        end
        (c["branches"] || []).each do |b|
          branch_rows << { client_id: cid, erp_branch_id: b["consecutive"],
                           name: b["name"], address: b["address"],
                           is_default: b["is_default"] || false }
        end
      end

      insert ClientTaxProfile, tax_rows
      insert ClientReceiptProfile, receipt_rows
      insert ClientBranch, branch_rows
    end

    # --- Productos + precio + SKUs de proveedor ---------------------------

    def import_products
      brand_by_erp = Brand.pluck(:erp_brand_id, :id).to_h

      rows = @data["products"].map do |p|
        { erp_product_id: p["erp_product_id"], description: p["description"],
          part_number: p["part_number"], model: p["model"],
          brand_id: brand_by_erp[p["erp_brand_id"]], stock: p["stock"],
          unit: p["unit"], max_discount: p["max_discount"],
          min_sale_quantity: p["min_sale_quantity"] }
      end
      insert Product, rows

      product_by_erp  = Product.pluck(:erp_product_id, :id).to_h
      supplier_by_erp = Supplier.pluck(:erp_supplier_id, :id).to_h

      price_rows, ps_rows = [], []
      @data["products"].each do |p|
        pid = product_by_erp[p["erp_product_id"]]
        next unless pid

        price_rows << { product_id: pid, public_price: p["public_price"],
                        wholesale_price: p["wholesale_price"], tax_rate: p["tax_rate"] }

        # Vínculo producto↔proveedor = `supplier_ids` (com_proveedor_has_producto,
        # la relación real que define el universo por proveedor) ∪ los SKUs
        # (com_producto_has_sku, que además traen el código del proveedor).
        sku_by_supplier = (p["supplier_skus"] || []).to_h { |sk| [ sk["erp_supplier_id"], sk["supplier_sku"] ] }
        erp_supplier_ids = (Array(p["supplier_ids"]) | sku_by_supplier.keys)
        erp_supplier_ids.each do |erp_sid|
          sid = supplier_by_erp[erp_sid]
          # Proveedores fuera de la rueda no existen localmente → se omiten.
          if sid.nil?
            @skipped_skus += 1
            next
          end
          ps_rows << { product_id: pid, supplier_id: sid, supplier_sku: sku_by_supplier[erp_sid] }
        end
      end

      insert Price, price_rows
      insert ProductSupplier, ps_rows
    end

    # --- Membresía capturista ↔ proveedor/marca (universo de productos) ----

    def import_people
      round           = BusinessRound.find_by(erp_round_id: @data["round"]["erp_round_id"])
      user_by_erp     = User.pluck(:erp_person_id, :id).to_h
      supplier_by_erp = Supplier.pluck(:erp_supplier_id, :id).to_h
      brand_by_erp    = Brand.pluck(:erp_brand_id, :id).to_h

      rows = []
      Array(@data["people"]).each do |m|
        uid = user_by_erp[m["erp_person_id"]]
        # Proveedor y marca son opcionales por separado (el ERP manda solo
        # uno u otro en renglones "solo proveedor"/"solo marca"), pero una
        # referencia que viene y no resuelve localmente es una membresía rota.
        sup_ref, brand_ref = m["erp_supplier_id"], m["erp_brand_id"]
        sid = sup_ref && supplier_by_erp[sup_ref]
        bid = brand_ref && brand_by_erp[brand_ref]
        broken_ref = (sup_ref && sid.nil?) || (brand_ref && bid.nil?)
        # Sin usuario local (capturista omitido por falta de contraseña), sin
        # proveedor NI marca, o con referencia rota → se omite y se reporta.
        if uid.nil? || broken_ref || (sup_ref.nil? && brand_ref.nil?)
          @skipped_people += 1
          next
        end
        rows << { business_round_id: round.id, user_id: uid, supplier_id: sid,
                  brand_id: bid, position: m["position"] || 1 }
      end
      insert BusinessRoundPerson, rows
    end

    # --- Helper ------------------------------------------------------------

    def insert(model, rows)
      model.insert_all(rows, record_timestamps: true) if rows.any?
      @stats[model.table_name] = rows.size
    end
  end
end
