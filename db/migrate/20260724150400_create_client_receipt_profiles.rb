class CreateClientReceiptProfiles < ActiveRecord::Migration[8.1]
  def change
    # Perfil de remisión del cliente. Un cliente puede tener varios.
    create_table :client_receipt_profiles do |t|
      t.references :client, null: false, foreign_key: true
      t.integer :erp_receipt_profile_id
      t.string  :name
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :client_receipt_profiles, :erp_receipt_profile_id
  end
end
