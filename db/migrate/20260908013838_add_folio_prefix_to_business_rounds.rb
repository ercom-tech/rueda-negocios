# Prefijo de los folios de la rueda (`cnf_rueda_negocios.prefijo` del ERP,
# varchar 4). Es lo que la app antepone a la clave de cada pedido en vez del
# "RN" fijo que traía en código, y lo que vuelve esa clave única entre ruedas
# — el ERP la guardará en `vta_pedido.clave_rueda` para saber de qué pedido de
# la rueda salió cada pedido suyo.
#
# Nullable a propósito: una rueda dada de alta antes de que la columna
# existiera lo trae vacío, y el pedido cae al respaldo `Order::DEFAULT_FOLIO_PREFIX`.
class AddFolioPrefixToBusinessRounds < ActiveRecord::Migration[8.1]
  def change
    add_column :business_rounds, :folio_prefix, :string
  end
end
