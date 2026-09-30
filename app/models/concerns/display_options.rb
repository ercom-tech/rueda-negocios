# Opciones de combo [nombre, id] por NOMBRE PARA MOSTRAR y en orden alfabético
# sin distinguir mayúsculas. Un solo lugar para proveedores y marcas: la 12ª
# auditoría encontró el mismo orden copiado en tres sitios —la ventanita del
# producto nuevo, los filtros de los reportes, la píldora de contexto— y las
# marcas ordenando de dos formas distintas (en Ruby y por la collation de la
# base), así que la misma lista podía salir en dos órdenes.
module DisplayOptions
  extend ActiveSupport::Concern

  class_methods do
    def display_options(records)
      records.map { |record| [ record.display_name, record.id ] }.sort_by { |name, _| name.downcase }
    end
  end
end
