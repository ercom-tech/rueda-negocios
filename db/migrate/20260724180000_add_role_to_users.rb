class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    # Rol local: capturista (ve solo sus pedidos) o server (el equipo-servidor,
    # ve todos los pedidos para transmitirlos al ERP). Mapeo fino con el ERP
    # (cnf_persona.id_rol) se define en el arco de sync.
    add_column :users, :role, :string, null: false, default: "capturista"
  end
end
