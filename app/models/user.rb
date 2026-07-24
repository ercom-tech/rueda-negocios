class User < ApplicationRecord
  # Capturista. Identidad y credenciales sincronizadas del ERP
  # (cnf_persona + cnf_persona_has_metodoidentifica). El hash del ERP es
  # bcrypt, así que `authenticate` lo valida directo, sin re-hashear.
  #
  # `validations: false` porque los usuarios entran por sync (solo traen el
  # digest); nunca fijamos contraseña desde la app. `authenticate` sigue
  # disponible.
  has_secure_password validations: false

  has_many :business_round_people, dependent: :destroy
  has_many :suppliers, through: :business_round_people

  validates :erp_person_id, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
  validates :password_digest, presence: true

  def full_name
    [name, paternal_surname, maternal_surname].compact_blank.join(" ")
  end

  # Proveedores del capturista en una rueda (cnf_rueda_negocios_persona),
  # en orden de `consecutivo`. Un usuario puede representar a varios.
  def suppliers_in(round)
    return [] unless round

    ids = business_round_people.where(business_round_id: round.id)
                               .order(:consecutivo).pluck(:supplier_id).uniq
    by_id = Supplier.where(id: ids).index_by(&:id)
    ids.filter_map { |id| by_id[id] }
  end
end
