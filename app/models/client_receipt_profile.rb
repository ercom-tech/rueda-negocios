class ClientReceiptProfile < ApplicationRecord
  # Perfil de remisión del cliente. Un cliente puede tener varios.

  belongs_to :client

  def label
    name.presence || "Remisión ##{id}"
  end
end
