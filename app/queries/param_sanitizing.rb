# Saneo de los parámetros que llegan por URL y se usan para consultar.
#
# Vive aquí, y no como método privado de quien lo necesita, porque el defecto
# que cubre ya se pagó dos veces: un `?user_id[]=1` llega como **arreglo** y un
# `?user_id[x]=1` como `ActionController::Parameters`, y sobre cualquiera de
# los dos un `to_i` levanta `NoMethodError` — o sea la pantalla de error de
# Rails en la laptop del evento. `OrdersFilter` lo resolvió en su momento y el
# reporte de productos, escrito después, volvió a caer (9ª auditoría).
module ParamSanitizing
  # El id más grande que cabe en un `bigint`. Uno mayor (`?supplier_id=` con 20
  # dígitos) pasaba el saneo y reventaba después, al armar SQL a mano, con
  # `IntegerOutOf64BitRange` — un 500 donde antes había "sin resultados" (12ª
  # auditoría).
  MAX_ID = (2**63) - 1

  module_function

  # Un id de catálogo: entero positivo que cabe en un bigint, o nil. Rechaza
  # arreglos, hashes y cadenas que no sean números — nunca levanta. En base
  # 10 explícita: `Integer("010")` es 8 (octal) y `"0x1f"` es 31, mientras
  # ActiveRecord lee "010" como 10 — `find` y `exists?` miraban registros
  # distintos con el mismo parámetro (17ª auditoría).
  def id(value)
    return nil unless value.is_a?(String) || value.is_a?(Integer)

    number = value.is_a?(Integer) ? value : Integer(value, 10, exception: false)
    number if number&.positive? && number <= MAX_ID
  end

  # Número de página para Pagy. Un `?page[]=2` hace que Pagy levante
  # `Pagy::VariableError`, que NO es `Pagy::OverflowError` y por tanto el
  # `rescue_from` del controlador no atrapa.
  def page(value)
    id(value) || 1
  end

  # Tamaño de página: solo uno de los permitidos. Un `?per_page[]=50` llega
  # como arreglo y el `to_i` que había en cada controlador levantaba
  # NoMethodError (13ª auditoría).
  def page_size(value, sizes)
    size = id(value)
    sizes.include?(size) ? size : sizes.first
  end

  # Texto libre: recortado, o nil.
  def text(value)
    value.strip.presence if value.is_a?(String)
  end
end
