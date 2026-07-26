class AddTrigramIndexesForSearch < ActiveRecord::Migration[8.1]
  # Los autocompletados de producto y cliente buscan con ILIKE '%q%' (comodín
  # inicial), que ningún btree puede servir → seq scan de ~13k productos en
  # cada tecla. pg_trgm + índices GIN los vuelven búsquedas por índice.
  def change
    enable_extension "pg_trgm"

    # Buscador de producto (Product.search).
    add_index :products, :description,  using: :gin, opclass: :gin_trgm_ops,
                                        name: "index_products_on_description_trgm"
    add_index :products, :model,        using: :gin, opclass: :gin_trgm_ops,
                                        name: "index_products_on_model_trgm"
    add_index :products, :part_number,  using: :gin, opclass: :gin_trgm_ops,
                                        name: "index_products_on_part_number_trgm"
    # El scope busca por CAST(erp_product_id AS TEXT) ILIKE — índice de
    # expresión (el opclass va inline: la opción opclass: solo aplica a columnas).
    add_index :products, "CAST(erp_product_id AS TEXT) gin_trgm_ops",
              using: :gin, name: "index_products_on_erp_product_id_text_trgm"
    add_index :product_suppliers, :supplier_sku, using: :gin, opclass: :gin_trgm_ops,
                                                 name: "index_product_suppliers_on_supplier_sku_trgm"

    # Buscador de cliente (OrdersController#client_search).
    add_index :clients, :name,            using: :gin, opclass: :gin_trgm_ops,
                                          name: "index_clients_on_name_trgm"
    add_index :clients, :commercial_name, using: :gin, opclass: :gin_trgm_ops,
                                          name: "index_clients_on_commercial_name_trgm"
    add_index :clients, :erp_client_key,  using: :gin, opclass: :gin_trgm_ops,
                                          name: "index_clients_on_erp_client_key_trgm"
  end
end
