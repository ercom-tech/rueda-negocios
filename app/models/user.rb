class User < ApplicationRecord
  # Capturista. Identidad y credenciales sincronizadas del ERP
  # (cnf_persona + cnf_persona_has_metodoidentifica). El hash del ERP es
  # bcrypt, así que `authenticate` lo valida directo, sin re-hashear.
  #
  # `validations: false` porque los usuarios entran por sync (solo traen el
  # digest); nunca fijamos contraseña desde la app. `authenticate` sigue
  # disponible.
  has_secure_password validations: false

  validates :erp_person_id, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
  validates :password_digest, presence: true

  def full_name
    [name, paternal_surname, maternal_surname].compact_blank.join(" ")
  end
end
