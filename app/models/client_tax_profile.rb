class ClientTaxProfile < ApplicationRecord
  # Perfil fiscal (RFC) del cliente. Un cliente puede tener varios.

  belongs_to :client
  belongs_to :default_cfdi_use, class_name: "CfdiUse", optional: true

  validates :rfc, presence: true

  def label
    [rfc, business_name].compact_blank.join(" — ")
  end
end
