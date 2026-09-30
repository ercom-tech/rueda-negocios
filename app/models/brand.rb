class Brand < ApplicationRecord
  include DisplayOptions
  # Marca (com_marca).

  has_many :products, dependent: :nullify

  has_and_belongs_to_many :suppliers, join_table: :brands_suppliers
  has_and_belongs_to_many :business_rounds, join_table: :business_round_brands

  validates :erp_brand_id, presence: true, uniqueness: true

  # Mismo nombre de método que `Supplier#display_name`, para que la pantalla que
  # muestra "proveedor o marca" (la píldora de contexto) no tenga que saber
  # cuál es. La marca no tiene razón social: su nombre es el que se ve.
  def display_name
    name
  end
end
