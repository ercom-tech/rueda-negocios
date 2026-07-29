class CreateLoginEvents < ActiveRecord::Migration[8.1]
  # Auditoría de inicios de sesión: un renglón por intento (exitoso o no).
  # Sobrevive al replace del sync-down: si el usuario se elimina, la FK anula
  # user_id pero el evento (con el username tecleado) permanece.
  def change
    create_table :login_events do |t|
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string :username, null: false
      t.boolean :success, null: false
      t.string :ip
      t.text :user_agent

      t.timestamps
    end
    add_index :login_events, :created_at
  end
end
