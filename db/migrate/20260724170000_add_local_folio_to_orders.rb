class AddLocalFolioToOrders < ActiveRecord::Migration[8.1]
  def change
    # Folio local (offline), asignado al enviar el pedido. El folio del ERP
    # (erp_folio) se asigna en el sync-up.
    add_column :orders, :local_folio, :string
    add_index :orders, :local_folio, unique: true
  end
end
