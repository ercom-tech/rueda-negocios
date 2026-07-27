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
  has_many :orders, dependent: :destroy

  # capturista: ve solo sus pedidos. server: el equipo-servidor, ve todos.
  enum :role, { capturista: "capturista", server: "server" }, default: "capturista"

  def can_see_all_orders?
    server?
  end

  validates :erp_person_id, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
  validates :password_digest, presence: true

  def full_name
    [name, paternal_surname, maternal_surname].compact_blank.join(" ")
  end

  # Proveedores del capturista en una rueda (cnf_rueda_negocios_persona),
  # en orden de `position` (el `consecutivo` del ERP). Un usuario puede
  # representar a varios.
  def suppliers_in(round)
    return [] unless round

    ids = business_round_people.where(business_round_id: round.id)
                               .order(:position).pluck(:supplier_id).uniq
    by_id = Supplier.where(id: ids).index_by(&:id)
    ids.filter_map { |id| by_id[id] }
  end

  # Universo de productos que el capturista puede vender en la rueda: los de
  # TODOS sus proveedores asignados ∪ los de sus marcas (regla del usuario,
  # 2026-07-26). Sin membresía → vacío: asignar capturistas a proveedor/marca
  # es responsabilidad operativa del ERP.
  def product_universe(round)
    return Product.none unless round

    memberships  = business_round_people.where(business_round_id: round.id)
    supplier_ids = memberships.pluck(:supplier_id).compact.uniq
    brand_ids    = memberships.pluck(:brand_id).compact.uniq
    return Product.none if supplier_ids.empty? && brand_ids.empty?

    Product.where(id: ProductSupplier.where(supplier_id: supplier_ids).select(:product_id))
           .or(Product.where(brand_id: brand_ids))
  end
end
