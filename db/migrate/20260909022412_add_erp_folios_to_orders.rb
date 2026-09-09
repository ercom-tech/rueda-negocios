# Los folios que el ERP devolvió por este pedido. Son varios desde que la
# transmisión lo parte allá: las partidas de catálogo se cortan cada 45 y los
# productos nuevos (genérico 999999) van en su propio pedido.
#
# `erp_folio` (singular) se conserva con el PRIMERO y no se retira: lo leen
# `Order#folio`, `OrdersSort` y `Sync::Guards` —"transmitido" sigue siendo
# "tiene folio del ERP"— y partirlo en dos conceptos a la vez sería cambiar la
# identidad del pedido y su guarda de transmisión en el mismo movimiento.
class AddErpFoliosToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :erp_folios, :string, array: true, default: []
  end
end
