class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.integer :erp_person_id, null: false   # cnf_persona.id_persona
      t.string  :username, null: false        # cnf_persona_has_metodoidentifica.username
      t.string  :password_hash, null: false   # hash del ERP (algoritmo por confirmar en Fase B)
      t.string  :name
      t.string  :paternal_surname
      t.string  :maternal_surname
      t.string  :rfc
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :users, :erp_person_id, unique: true
    add_index :users, :username, unique: true
  end
end
