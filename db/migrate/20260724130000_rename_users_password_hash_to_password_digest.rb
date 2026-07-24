class RenameUsersPasswordHashToPasswordDigest < ActiveRecord::Migration[8.1]
  def change
    # El ERP guarda bcrypt; usamos la columna convencional de Rails para que
    # `has_secure_password` valide el hash sincronizado sin re-hashear.
    rename_column :users, :password_hash, :password_digest
  end
end
