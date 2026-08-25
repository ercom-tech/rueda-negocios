module Sync
  # Puebla el Postgres local con el dataset de una rueda (respuesta de
  # `GET /ruedas/:id/export` de rueda-api). Es un **refresh pre-evento**:
  # deja el catálogo local idéntico al export (replace), no un merge.
  #
  # Guarda: aborta si hay CUALQUIER pedido que solo viva en la laptop —
  # borradores (capturas en curso) o capturados sin transmitir (ventas reales
  # que aún no llegan al ERP). Los transmitidos no bloquean: ya están en el ERP
  # y se purgan antes del replace, cosa que el modal advierte con su número.
  # Así el refresh entre días del evento es transmitir → obtener información.
  # Misma regla y misma redacción que "Cerrar rueda" (Sync::Guards).
  #
  # Usuarios: mismo REPLACE que las demás tablas — los capturistas quedan
  # idénticos al export (upsert por `erp_person_id` + limpieza de los que no
  # vienen, incluso si el export trae cero: eso es problema operativo del ERP).
  # Única excepción: el usuario `server` (seedeado) sobrevive siempre — es
  # infraestructura de la app, no dato del ERP.
  #
  # Alcance: las 10 entidades del export, incluida la membresía
  # capturista↔proveedor/marca (`people` → business_round_people), que define
  # el universo de productos de cada capturista. Las demás tablas de membresía
  # (brands_suppliers, business_round_*) siguen sin venir en el export; solo se
  # vacían para que el replace no choque con FKs.
  class Down
    # Se levanta cuando la guarda impide correr el sync (hay pedidos).
    class GuardError < StandardError; end

    # El replace borra todos los pedidos locales, así que un borrador o un
    # capturado sin transmitir se perdería. Método de clase (no usa estado del
    # objeto) para que el controlador pueda preguntarlo ANTES de crear el
    # SyncRun — una condición previa no debe quedar registrada como una corrida
    # fallida; `run!` lo repite para cubrir `rake sync:down` y el job.
    def self.guard!
      Guards.no_local_orders!(GuardError, "al obtener la información")
    end

    def initialize(data)
      @data = data
      @stats = {}
      @skipped_users = []
      @skipped_user_ids = []
      @removed_users = []
      @skipped_skus = 0
      # Set: se reporta por persona, no por renglón de membresía.
      @skipped_people = Set.new
      @purged_orders = 0
      @skipped_promotion_products = 0
      # Set: se reporta por producto, no por renglón.
      @shared_promotion_products = Set.new
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
      import_promotions
      self
    end

    def summary
      { entities: @stats, skipped_users: @skipped_users,
        removed_users: @removed_users, skipped_skus: @skipped_skus,
        skipped_people: @skipped_people.to_a, purged_orders: @purged_orders,
        skipped_promotion_products: @skipped_promotion_products,
        shared_promotion_products: @shared_promotion_products.to_a,
        # La captura fuera de catálogo depende de que el genérico venga en el
        # dataset (export viejo o baja en el ERP lo dejan fuera): sin este
        # aviso, la UI lo prometía en bucle sin que nada lo delatara (6ª aud.).
        missing_generic: !Product.joins(:price).where(erp_product_id: Product::GENERIC_ERP_ID)
                                 .where.not(prices: { tax_rate: nil }).exists? }
    end

    private

    # Al llegar aquí la guarda ya garantizó que solo quedan TRANSMITIDOS: no
    # bloquean (viven en el ERP) pero sus FKs chocarían con el replace del
    # catálogo, así que se purgan y se reporta cuántos. El borrado se acota a
    # lo que la guarda autorizó y se vuelve a comprobar después, dentro de la
    # misma transacción: entre la guarda y el borrado otra conexión aún puede
    # colar un pedido (un POST que pasó la pausa antes del alta de la
    # corrida), y con `Order.destroy_all` esa venta se perdía en silencio —
    # mismo patrón que CloseRound (ver docs/convenciones-codigo.md).
    def purge_local_orders!
      @purged_orders = Order.transmitted.count
      # `purge_transmitted!` y no `destroy_all`: el candado de promoción de
      # OrderItem aborta el destroy y las partidas sobrevivían a la purga, con
      # el replace del catálogo reventando después por FK (ver Order).
      Order.purge_transmitted! if @purged_orders.positive?
      Guards.no_local_orders!(GuardError, "al obtener la información")
    end

    # Borra el catálogo (hijos → padres) para repoblarlo idéntico al export.
    # Las tablas de membresía se vacían primero: cuelgan de brands/suppliers/
    # salespeople/clients/rounds y bloquearían el delete por FK.
    def clear_catalog!
      # Las promociones cuelgan de products: van antes que el bloque que lo
      # borra, o el delete choca por FK.
      [ PromotionGift, PromotionProduct, PromotionTier, Promotion,
       BusinessRoundPerson, BusinessRoundClient ].each(&:delete_all)
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
          @skipped_user_ids << u["erp_person_id"]
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

        # Sin default inventado: el export ordena por RFC alfabético, y en los
        # clientes multi-RFC nativos el primer RFC solo es el que se usa el 49%
        # de las veces — el día que una pantalla preseleccionara "el default",
        # la mitad saldría al RFC equivocado. Ninguna pantalla lo lee hoy; el
        # de sucursal sí es dato real del ERP y ese se conserva.
        (c["tax_profiles"] || []).each do |t|
          tax_rows << { client_id: cid, rfc: t["rfc"], business_name: t["business_name"],
                        default_cfdi_use_id: cfdi_by_code[t["default_cfdi_use"]],
                        is_default: false }
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
                        wholesale_price: p["wholesale_price"],
                        credit_wholesale_price: p["credit_wholesale_price"],
                        tax_rate: p["tax_rate"] }

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

      # Para nombrar a los afectados en el aviso del panel: sin nombres,
      # "pide que los asignen" no era accionable (6ª auditoría).
      username_by_erp = User.pluck(:erp_person_id, :username).to_h

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
        # El dueño se omitió por credencial ilegible: ya se reportó en
        # `skipped_users` y su membresía cae con él. Contarlo también aquí
        # duplicaba el aviso con el diagnóstico equivocado ("sin proveedor ni
        # marca"), que mandaba al operador a corregir lo que no está roto.
        next if uid.nil? && @skipped_user_ids.include?(m["erp_person_id"])

        # Sin usuario local (persona que no vino en el export de usuarios),
        # sin proveedor NI marca, o con referencia rota → la membresía se
        # omite y se reporta POR PERSONA (contar renglones inflaba el aviso:
        # un capturista con 3 renglones rotos salía como "3 capturistas").
        if uid.nil? || broken_ref || (sup_ref.nil? && brand_ref.nil?)
          @skipped_people << (username_by_erp[m["erp_person_id"]] || "persona #{m['erp_person_id']}")
          next
        end
        rows << { business_round_id: round.id, user_id: uid, supplier_id: sid,
                  brand_id: bid, position: m["position"] || 1 }
      end
      insert BusinessRoundPerson, rows
    end

    # --- Promociones de la rueda ------------------------------------------

    # Espejo de vta_promocion y sus tres tablas hijas. `Array()` por
    # compatibilidad con exports viejos: una API sin promociones deja la
    # rueda sin ellas, no revienta el sync.
    def import_promotions
      promos = Array(@data["promotions"])
      rows = promos.map do |p|
        { erp_promotion_id: p["erp_promotion_id"], code: p["code"], name: p["name"],
          starts_on: p["starts_on"], ends_on: p["ends_on"] }
      end
      insert Promotion, rows
      return if rows.empty?

      promo_by_erp   = Promotion.pluck(:erp_promotion_id, :id).to_h
      product_by_erp = Product.pluck(:erp_product_id, :id).to_h

      import_promotion_tiers(promos, promo_by_erp, product_by_erp)
      import_promotion_products(promos, promo_by_erp, product_by_erp)
    end

    def import_promotion_tiers(promos, promo_by_erp, product_by_erp)
      tier_rows = []
      promos.each do |p|
        pid = promo_by_erp[p["erp_promotion_id"]]
        Array(p["tiers"]).each do |t|
          tier_rows << { promotion_id: pid, erp_consecutive: t["erp_consecutive"],
                         condition_kind: t["condition_kind"], unit: t["unit"],
                         quantity_from: t["quantity_from"], quantity_to: t["quantity_to"],
                         discount_percent: t["discount_percent"] }
        end
      end
      insert PromotionTier, tier_rows
      return if tier_rows.empty?

      # Los regalos cuelgan del escalón: hace falta su id local, y el par
      # (promoción, consecutivo) es la llave que los empareja.
      tier_by_key = PromotionTier.pluck(:promotion_id, :erp_consecutive, :id)
                                 .to_h { |promo_id, consec, id| [ [ promo_id, consec ], id ] }
      gift_rows = []
      promos.each do |p|
        pid = promo_by_erp[p["erp_promotion_id"]]
        Array(p["tiers"]).each do |t|
          tier_id = tier_by_key[[ pid, t["erp_consecutive"] ]]
          Array(t["gifts"]).each do |g|
            product_id = product_by_erp[g["erp_product_id"]]
            # Un regalo cuyo producto no llegó al catálogo no se puede
            # materializar. El export ya los incluye a propósito (el esmeril
            # de FANDELI no es de ninguna marca ni proveedor de la rueda);
            # si aun así falta, se omite y se cuenta.
            if tier_id.nil? || product_id.nil?
              @skipped_promotion_products += 1
              next
            end
            gift_rows << { promotion_tier_id: tier_id, product_id: product_id,
                           quantity: g["quantity"] }
          end
        end
      end
      insert PromotionGift, gift_rows
    end

    def import_promotion_products(promos, promo_by_erp, product_by_erp)
      code_rows = []
      # Un producto en dos promociones rompe la regla "una partida participa
      # en una sola promoción": hoy no pasa (los 6,046 de la rueda están cada
      # uno en una), pero es dato del ERP y puede cambiar sin avisar. Se
      # conserva la primera y se reporta, en vez de dejar que la pantalla
      # elija en silencio cuál descuento ofrece.
      seen = Set.new
      promos.each do |p|
        pid = promo_by_erp[p["erp_promotion_id"]]
        Array(p["products"]).each do |c|
          product_id = product_by_erp[c["erp_product_id"]]
          if product_id.nil?
            @skipped_promotion_products += 1
            next
          end
          if seen.include?(product_id)
            @shared_promotion_products << c["erp_product_id"]
            next
          end
          seen << product_id
          code_rows << { promotion_id: pid, product_id: product_id,
                         discount_percent: c["discount_percent"] }
        end
      end
      insert PromotionProduct, code_rows
    end

    # --- Helper ------------------------------------------------------------

    def insert(model, rows)
      model.insert_all(rows, record_timestamps: true) if rows.any?
      @stats[model.table_name] = rows.size
    end
  end
end
