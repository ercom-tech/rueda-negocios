class CreateBusinessRoundPeople < ActiveRecord::Migration[8.1]
  def change
    # cnf_rueda_negocios_persona: persona (usuario/capturista) ligada a un
    # proveedor (y marca opcional) dentro de una rueda.
    create_table :business_round_people do |t|
      t.references :business_round, null: false, foreign_key: true
      t.references :user,           null: false, foreign_key: true
      t.references :supplier,       null: false, foreign_key: true
      t.references :brand,          null: true,  foreign_key: true
      t.integer    :consecutivo,    null: false, default: 1

      t.timestamps
    end

    add_index :business_round_people, [:business_round_id, :user_id, :consecutivo],
              unique: true, name: "idx_brp_round_user_consec"
  end
end
