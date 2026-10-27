class AddDocumentToOrders < ActiveRecord::Migration[8.1]
  # Las cotizaciones viven en la misma tabla que los pedidos (decisión del
  # usuario 2026-10-27): comparten partidas, promociones, Cotizador, totales y
  # la pantalla de captura entera. `document` dice cuál es cuál: `sale` es todo
  # lo que ya existía; `estimate`, la cotización.
  #
  # La cotización puede ser de "cliente genérico" —alguien que no está en el
  # catálogo de la rueda—, así que `client_id` pasa a admitir vacío. El CHECK
  # es lo que impide que un pedido sin cliente exista venga de donde venga: un
  # pedido así se transmitiría al ERP sin a quién venderle.
  #
  # `kind` (factura/remisión) solo tiene sentido con cliente: la genérica no
  # se factura ni se remite. Se quita el NOT NULL y el default "invoice", que
  # de todos modos nadie usaba (el paso 1 siempre lo calcula del cliente).
  def change
    add_column :orders, :document, :string, null: false, default: "sale"
    add_index  :orders, :document

    change_column_null    :orders, :client_id, true
    change_column_null    :orders, :kind, true
    change_column_default :orders, :kind, from: "invoice", to: nil

    add_check_constraint :orders, "document = 'estimate' OR client_id IS NOT NULL",
                         name: "orders_sale_requires_client"

    # Consecutivo del folio de cotización (COT-000001), aparte del de pedidos
    # y aparte del id: no retrocede cuando se borran cotizaciones, para que un
    # número no se repita a media rueda. Vive en `settings` y no en una
    # secuencia de Postgres porque `db/schema.rb` no volcaría la secuencia y
    # la base de pruebas se quedaría sin ella.
    add_column :settings, :last_estimate_number, :integer, null: false, default: 0
  end
end
