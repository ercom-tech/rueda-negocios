module Sync
  # Puebla el Postgres local con el dataset de una rueda (respuesta de
  # `GET /ruedas/:id/export` de rueda-api). Es un **refresh pre-evento**:
  # deja el catálogo local idéntico al export (replace), no un merge.
  #
  # Guarda: aborta si ya hay pedidos capturados — el sync-down no debe correr
  # sobre pedidos existentes (evita romper FKs y perder captura).
  #
  # Usuarios: excepción a la regla. Los capturistas se mergean por su llave del
  # ERP (`erp_person_id`) y se limpian los que ya no vienen; pero el `role` es
  # estado propio de la app, así que NO se pisa y los `server` (seedeados) se
  # preservan siempre.
  #
  # Alcance: las 8 entidades del export. Las tablas de membresía de la rueda
  # (business_round_people, brands_suppliers, business_round_*) quedan para un
  # arco posterior — el export todavía no las incluye; aquí solo se vacían para
  # que el replace no choque con FKs.
  class Down
    # Se levanta cuando la guarda impide correr el sync (hay pedidos).
    class GuardError < StandardError; end

    def initialize(data)
      @data = data
      @stats = {}
      @skipped_users = []
      @removed_users = []
      @skipped_skus = 0
    end

    def run!
      guard!
      clear_catalog!
      import_cfdi_uses
      import_brands
      import_suppliers
      import_salespeople
      import_round
      import_users
      import_clients
      import_products
      self
    end

    def summary
      { entities: @stats, skipped_users: @skipped_users,
        removed_users: @removed_users, skipped_skus: @skipped_skus }
    end

    private

    # --- Guarda y limpieza ------------------------------------------------

    def guard!
      return unless Order.exists?

      raise GuardError,
            "Hay #{Order.count} pedido(s) capturado(s). El sync-down es un " \
            "refresh pre-evento y no debe correr sobre pedidos existentes."
    end

    # Borra el catálogo (hijos → padres) para repoblarlo idéntico al export.
    # Las tablas de membresía se vacían primero: cuelgan de brands/suppliers/
    # salespeople/clients/rounds y bloquearían el delete por FK.
    def clear_catalog!
      [BusinessRoundPerson, BusinessRoundClient].each(&:delete_all)
      exec_delete("business_round_brands")
      exec_delete("business_round_suppliers")
      exec_delete("business_round_salespeople")
      exec_delete("brands_suppliers")

      [Price, ProductSupplier, Product,
       ClientTaxProfile, ClientReceiptProfile, ClientBranch, Client,
       Salesperson, Supplier, Brand, CfdiUse, BusinessRound].each(&:delete_all)
    end

    def exec_delete(table)
      ActiveRecord::Base.connection.execute("DELETE FROM #{table}")
    end

    # --- Catálogos base (sin dependencias) --------------------------------

    def import_cfdi_uses
      rows = @data["cfdi_uses"].map { |c| { code: c["code"], description: c["description"] } }
      insert CfdiUse, rows
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
      insert BusinessRound, [row]
    end

    # --- Usuarios (capturistas): merge + cleanup, preservando servers -----

    def import_users
      erp_keys = @data["users"].map { |u| u["erp_person_id"] }

      rows = []
      @data["users"].each do |u|
        if u["password_hash"].to_s.empty?
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

      # Cleanup: capturistas que ya no vienen del ERP. Nunca borra un `server`
      # (el seedeado no está en el export y debe sobrevivir).
      stale = User.capturista.where.not(erp_person_id: erp_keys)
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
          unit: p["unit"], max_discount: p["max_discount"] }
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

        (p["supplier_skus"] || []).each do |sk|
          sid = supplier_by_erp[sk["erp_supplier_id"]]
          # SKUs de proveedores fuera de la rueda no tienen proveedor local → se omiten.
          if sid.nil?
            @skipped_skus += 1
            next
          end
          ps_rows << { product_id: pid, supplier_id: sid, supplier_sku: sk["supplier_sku"] }
        end
      end

      insert Price, price_rows
      insert ProductSupplier, ps_rows
    end

    # --- Helper ------------------------------------------------------------

    def insert(model, rows)
      model.insert_all(rows, record_timestamps: true) if rows.any?
      @stats[model.table_name] = rows.size
    end
  end
end
