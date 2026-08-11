class ClientBranch < ApplicationRecord
  # Sucursal / dirección de entrega del cliente. Un cliente puede tener varias.

  belongs_to :client

  def label
    [ name, address ].compact_blank.join(" — ")
  end
end
