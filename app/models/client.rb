class Client < ApplicationRecord
  # Cliente (vta_cliente).

  belongs_to :salesperson, optional: true

  has_many :business_round_clients, dependent: :destroy
  has_many :business_rounds, through: :business_round_clients

  has_many :tax_profiles,     class_name: "ClientTaxProfile",     dependent: :destroy
  has_many :receipt_profiles, class_name: "ClientReceiptProfile", dependent: :destroy
  has_many :branches,         class_name: "ClientBranch",         dependent: :destroy
  has_many :orders, dependent: :destroy

  validates :erp_client_key, presence: true, uniqueness: true

  # Buscador del paso 1 (clave, nombre o nombre comercial). Vive aquí y no en
  # el controlador —espejo de `Product.search`— porque "buscar cliente" tiene
  # una relevancia propia que las demás pantallas necesitan reusar: si se queda
  # como método privado de OrdersController, la siguiente lo copia y a partir
  # de ahí buscar un cliente significa dos cosas distintas según dónde estés.
  #
  # Relevancia: primero los que EMPIEZAN con lo tecleado (en comercial o
  # nombre), luego alfabético por comercial (o nombre si no hay comercial).

  # Mismo tope que el buscador de producto: los dos se recorren igual, y que
  # diverjan en silencio deja una pantalla avisando del corte y la otra no.
  SEARCH_LIMIT = 50

  scope :search, ->(query) {
    q = sanitize_sql_like(query.to_s.strip)
    next none if q.blank?

    relevance = sanitize_sql_array([
      "CASE WHEN commercial_name ILIKE :p OR name ILIKE :p THEN 0 ELSE 1 END, " \
      "COALESCE(NULLIF(commercial_name, ''), name)", { p: "#{q}%" }
    ])
    includes(:salesperson)
      .where("name ILIKE :q OR commercial_name ILIKE :q OR erp_client_key ILIKE :q", q: "%#{q}%")
      .order(Arel.sql(relevance))
  }
end
