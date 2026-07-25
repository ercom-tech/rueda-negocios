class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      # Contexto de captura. (No lleva proveedor: un pedido puede mezclar
      # productos de distintos proveedores; el proveedor activo es solo
      # contexto de la sesión, no restringe el pedido.)
      t.references :user,           null: false, foreign_key: true  # capturista
      t.references :business_round, null: false, foreign_key: true
      t.references :client,         null: false, foreign_key: true

      # Encabezado (paso 1).
      t.string :kind, null: false, default: "invoice"  # invoice (Factura) / remission (Remisión)
      t.references :client_tax_profile,     foreign_key: true, null: true  # RFC elegido (Factura)
      t.references :client_receipt_profile, foreign_key: true, null: true  # remisión elegida
      t.references :client_branch,          foreign_key: true, null: true  # sucursal de entrega
      t.references :cfdi_use,               foreign_key: true, null: true  # uso de CFDI elegido

      t.string :status, null: false, default: "draft"  # draft / submitted
      t.string :erp_folio  # folio del ERP; nulo hasta el sync-up

      t.timestamps
    end
  end
end
