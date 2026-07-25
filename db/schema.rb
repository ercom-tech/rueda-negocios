# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_24_160300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "brands", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.integer "erp_brand_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["erp_brand_id"], name: "index_brands_on_erp_brand_id", unique: true
  end

  create_table "brands_suppliers", id: false, force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "supplier_id", null: false
    t.index ["brand_id", "supplier_id"], name: "index_brands_suppliers_on_brand_id_and_supplier_id", unique: true
    t.index ["brand_id"], name: "index_brands_suppliers_on_brand_id"
    t.index ["supplier_id"], name: "index_brands_suppliers_on_supplier_id"
  end

  create_table "business_round_brands", id: false, force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "business_round_id", null: false
    t.index ["brand_id"], name: "index_business_round_brands_on_brand_id"
    t.index ["business_round_id", "brand_id"], name: "idx_brb_round_brand", unique: true
    t.index ["business_round_id"], name: "index_business_round_brands_on_business_round_id"
  end

  create_table "business_round_clients", force: :cascade do |t|
    t.boolean "approved_credit", default: false, null: false
    t.boolean "approved_sales", default: false, null: false
    t.decimal "authorized_credit_limit", precision: 14, scale: 2
    t.bigint "business_round_id", null: false
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.bigint "salesperson_id"
    t.datetime "updated_at", null: false
    t.index ["business_round_id", "client_id"], name: "idx_brc_round_client", unique: true
    t.index ["business_round_id"], name: "index_business_round_clients_on_business_round_id"
    t.index ["client_id"], name: "index_business_round_clients_on_client_id"
    t.index ["salesperson_id"], name: "index_business_round_clients_on_salesperson_id"
  end

  create_table "business_round_people", force: :cascade do |t|
    t.bigint "brand_id"
    t.bigint "business_round_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 1, null: false
    t.bigint "supplier_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["brand_id"], name: "index_business_round_people_on_brand_id"
    t.index ["business_round_id", "user_id", "position"], name: "idx_brp_round_user_position", unique: true
    t.index ["business_round_id"], name: "index_business_round_people_on_business_round_id"
    t.index ["supplier_id"], name: "index_business_round_people_on_supplier_id"
    t.index ["user_id"], name: "index_business_round_people_on_user_id"
  end

  create_table "business_round_salespeople", id: false, force: :cascade do |t|
    t.bigint "business_round_id", null: false
    t.bigint "salesperson_id", null: false
    t.index ["business_round_id", "salesperson_id"], name: "idx_brsp_round_salesperson", unique: true
    t.index ["business_round_id"], name: "index_business_round_salespeople_on_business_round_id"
    t.index ["salesperson_id"], name: "index_business_round_salespeople_on_salesperson_id"
  end

  create_table "business_round_suppliers", id: false, force: :cascade do |t|
    t.bigint "business_round_id", null: false
    t.bigint "supplier_id", null: false
    t.index ["business_round_id", "supplier_id"], name: "idx_brs_round_supplier", unique: true
    t.index ["business_round_id"], name: "index_business_round_suppliers_on_business_round_id"
    t.index ["supplier_id"], name: "index_business_round_suppliers_on_supplier_id"
  end

  create_table "business_rounds", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.date "ends_on"
    t.integer "erp_round_id", null: false
    t.string "location"
    t.string "name", null: false
    t.date "starts_on"
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["erp_round_id"], name: "index_business_rounds_on_erp_round_id", unique: true
  end

  create_table "cfdi_uses", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_cfdi_uses_on_code", unique: true
  end

  create_table "client_branches", force: :cascade do |t|
    t.string "address"
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.integer "erp_branch_id"
    t.boolean "is_default", default: false, null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_client_branches_on_client_id"
    t.index ["erp_branch_id"], name: "index_client_branches_on_erp_branch_id"
  end

  create_table "client_receipt_profiles", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.integer "erp_receipt_profile_id"
    t.boolean "is_default", default: false, null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_client_receipt_profiles_on_client_id"
    t.index ["erp_receipt_profile_id"], name: "index_client_receipt_profiles_on_erp_receipt_profile_id"
  end

  create_table "client_tax_profiles", force: :cascade do |t|
    t.string "business_name"
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.bigint "default_cfdi_use_id"
    t.integer "erp_tax_profile_id"
    t.boolean "is_default", default: false, null: false
    t.string "rfc", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_client_tax_profiles_on_client_id"
    t.index ["default_cfdi_use_id"], name: "index_client_tax_profiles_on_default_cfdi_use_id"
    t.index ["erp_tax_profile_id"], name: "index_client_tax_profiles_on_erp_tax_profile_id"
  end

  create_table "clients", force: :cascade do |t|
    t.boolean "approved", default: false, null: false
    t.string "commercial_name"
    t.datetime "created_at", null: false
    t.integer "credit_days"
    t.decimal "credit_limit", precision: 14, scale: 2
    t.string "email"
    t.string "erp_client_key", null: false
    t.string "name"
    t.bigint "salesperson_id"
    t.datetime "updated_at", null: false
    t.index ["erp_client_key"], name: "index_clients_on_erp_client_key", unique: true
    t.index ["salesperson_id"], name: "index_clients_on_salesperson_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "description"
    t.decimal "discount_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.bigint "order_id", null: false
    t.string "part_number"
    t.integer "position", default: 1, null: false
    t.bigint "product_id"
    t.decimal "quantity", precision: 14, scale: 3, default: "1.0", null: false
    t.decimal "tax_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.string "unit"
    t.decimal "unit_price", precision: 14, scale: 4, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "position"], name: "index_order_items_on_order_id_and_position"
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "business_round_id", null: false
    t.bigint "cfdi_use_id"
    t.bigint "client_branch_id"
    t.bigint "client_id", null: false
    t.bigint "client_receipt_profile_id"
    t.bigint "client_tax_profile_id"
    t.datetime "created_at", null: false
    t.string "erp_folio"
    t.string "kind", default: "invoice", null: false
    t.text "observations"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["business_round_id"], name: "index_orders_on_business_round_id"
    t.index ["cfdi_use_id"], name: "index_orders_on_cfdi_use_id"
    t.index ["client_branch_id"], name: "index_orders_on_client_branch_id"
    t.index ["client_id"], name: "index_orders_on_client_id"
    t.index ["client_receipt_profile_id"], name: "index_orders_on_client_receipt_profile_id"
    t.index ["client_tax_profile_id"], name: "index_orders_on_client_tax_profile_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "prices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.decimal "public_price", precision: 14, scale: 4
    t.decimal "tax_rate", precision: 5, scale: 2
    t.datetime "updated_at", null: false
    t.decimal "wholesale_price", precision: 14, scale: 4
    t.index ["product_id"], name: "index_prices_on_product_id", unique: true
  end

  create_table "product_suppliers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.bigint "supplier_id", null: false
    t.string "supplier_sku"
    t.datetime "updated_at", null: false
    t.index ["product_id", "supplier_id"], name: "index_product_suppliers_on_product_id_and_supplier_id", unique: true
    t.index ["product_id"], name: "index_product_suppliers_on_product_id"
    t.index ["supplier_id"], name: "index_product_suppliers_on_supplier_id"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "brand_id"
    t.datetime "created_at", null: false
    t.string "description"
    t.integer "erp_product_id", null: false
    t.decimal "max_discount", precision: 5, scale: 2
    t.decimal "min_sale_quantity", precision: 14, scale: 3
    t.string "model"
    t.string "part_number"
    t.decimal "stock", precision: 14, scale: 2
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["erp_product_id"], name: "index_products_on_erp_product_id", unique: true
  end

  create_table "salespeople", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "erp_person_id"
    t.integer "erp_salesperson_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["erp_salesperson_id"], name: "index_salespeople_on_erp_salesperson_id", unique: true
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "code"
    t.string "commercial_name"
    t.datetime "created_at", null: false
    t.integer "erp_supplier_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["erp_supplier_id"], name: "index_suppliers_on_erp_supplier_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "erp_person_id", null: false
    t.string "maternal_surname"
    t.string "name"
    t.string "password_digest", null: false
    t.string "paternal_surname"
    t.string "rfc"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["erp_person_id"], name: "index_users_on_erp_person_id", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "brands_suppliers", "brands"
  add_foreign_key "brands_suppliers", "suppliers"
  add_foreign_key "business_round_brands", "brands"
  add_foreign_key "business_round_brands", "business_rounds"
  add_foreign_key "business_round_clients", "business_rounds"
  add_foreign_key "business_round_clients", "clients"
  add_foreign_key "business_round_clients", "salespeople"
  add_foreign_key "business_round_people", "brands"
  add_foreign_key "business_round_people", "business_rounds"
  add_foreign_key "business_round_people", "suppliers"
  add_foreign_key "business_round_people", "users"
  add_foreign_key "business_round_salespeople", "business_rounds"
  add_foreign_key "business_round_salespeople", "salespeople"
  add_foreign_key "business_round_suppliers", "business_rounds"
  add_foreign_key "business_round_suppliers", "suppliers"
  add_foreign_key "client_branches", "clients"
  add_foreign_key "client_receipt_profiles", "clients"
  add_foreign_key "client_tax_profiles", "cfdi_uses", column: "default_cfdi_use_id"
  add_foreign_key "client_tax_profiles", "clients"
  add_foreign_key "clients", "salespeople"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "business_rounds"
  add_foreign_key "orders", "cfdi_uses"
  add_foreign_key "orders", "client_branches"
  add_foreign_key "orders", "client_receipt_profiles"
  add_foreign_key "orders", "client_tax_profiles"
  add_foreign_key "orders", "clients"
  add_foreign_key "orders", "users"
  add_foreign_key "prices", "products"
  add_foreign_key "product_suppliers", "products"
  add_foreign_key "product_suppliers", "suppliers"
  add_foreign_key "products", "brands"
end
