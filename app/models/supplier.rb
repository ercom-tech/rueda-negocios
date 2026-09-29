class Supplier < ApplicationRecord
  # Proveedor (com_proveedor).

  has_and_belongs_to_many :brands, join_table: :brands_suppliers

  has_many :product_suppliers, dependent: :destroy
  has_many :products, through: :product_suppliers

  has_and_belongs_to_many :business_rounds, join_table: :business_round_suppliers

  has_many :business_round_people, dependent: :destroy

  validates :erp_supplier_id, presence: true, uniqueness: true

  # Como lo reconoce la gente: "FAMA", no "FAMA TECHNOLOGY FOUNDRY S.A. DE
  # C.V.". La razón social solo cuando el catálogo no trae el nombre comercial.
  # Es EL nombre del proveedor en toda pantalla (homologado 2026-09-29): la
  # ventanita del producto nuevo decía "STIHL" y la barra de arriba "STIHL S.A.
  # DE C.V." en la misma pantalla.
  def display_name
    commercial_name.presence || name
  end
end
