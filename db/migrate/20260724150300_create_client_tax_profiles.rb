class CreateClientTaxProfiles < ActiveRecord::Migration[8.1]
  def change
    # Perfil fiscal del cliente (RFC + razón social + uso CFDI por defecto).
    # Un cliente puede tener varios (varias claves fiscales bajo la misma clave).
    create_table :client_tax_profiles do |t|
      t.references :client, null: false, foreign_key: true
      t.integer :erp_tax_profile_id
      t.string  :rfc, null: false
      t.string  :business_name
      t.references :default_cfdi_use, foreign_key: { to_table: :cfdi_uses }, null: true
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :client_tax_profiles, :erp_tax_profile_id
  end
end
