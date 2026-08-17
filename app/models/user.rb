class User < ApplicationRecord
  # Capturista. Identidad y credenciales sincronizadas del ERP
  # (cnf_persona + cnf_persona_has_metodoidentifica). El hash del ERP es
  # bcrypt, así que `authenticate` lo valida directo, sin re-hashear.
  #
  # `validations: false` porque los usuarios entran por sync (solo traen el
  # digest); nunca fijamos contraseña desde la app. `authenticate` sigue
  # disponible.
  has_secure_password validations: false
  # Sesión única por usuario ("el último login gana"): cada login regenera el
  # token e invalida las cookies de sesiones anteriores (ver Sessions#create y
  # el guard require_current_session).
  has_secure_token :session_token

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
    [ name, paternal_surname, maternal_surname ].compact_blank.join(" ")
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

  # Marcas del capturista en una rueda (cnf_rueda_negocios_persona), en orden
  # de `position` — espejo de suppliers_in para las membresías de marca.
  def brands_in(round)
    return [] unless round

    ids = business_round_people.where(business_round_id: round.id)
                               .order(:position).pluck(:brand_id).uniq
    by_id = Brand.where(id: ids).index_by(&:id)
    ids.filter_map { |id| by_id[id] }
  end

  # Universo de productos que el capturista puede vender en la rueda: los de
  # TODOS sus proveedores asignados ∪ los de sus marcas (regla del usuario,
  # 2026-07-26) ∪ el genérico 999999, que es de todos. Sin membresía → solo
  # el genérico: asignar capturistas a proveedor/marca sigue siendo
  # responsabilidad operativa del ERP.
  def product_universe(round)
    return Product.none unless round

    memberships  = business_round_people.where(business_round_id: round.id)
    supplier_ids = memberships.pluck(:supplier_id).compact.uniq
    brand_ids    = memberships.pluck(:brand_id).compact.uniq

    # El genérico 999999 ("fuera de catálogo") es de todos: no exige
    # membresía — incluso un capturista sin proveedor ni marca puede capturar
    # con él (decisión FECEGO 2026-08-17).
    generic = Product.where(erp_product_id: Product::GENERIC_ERP_ID)
    return generic if supplier_ids.empty? && brand_ids.empty?

    Product.where(id: ProductSupplier.where(supplier_id: supplier_ids).select(:product_id))
           .or(Product.where(brand_id: brand_ids))
           .or(generic)
  end
end
