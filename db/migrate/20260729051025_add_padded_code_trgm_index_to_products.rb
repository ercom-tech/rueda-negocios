class AddPaddedCodeTrgmIndexToProducts < ActiveRecord::Migration[8.1]
  # La búsqueda compara contra el código FECEGO padded a 6 dígitos
  # (LPAD(erp_product_id::text, 6, '0') ILIKE %q%): índice trigram de
  # expresión para que esa rama no caiga en seq scan por keystroke.
  def change
    add_index :products, "LPAD(CAST(erp_product_id AS TEXT), 6, '0') gin_trgm_ops",
              using: :gin, name: "index_products_on_padded_code_trgm"
  end
end
