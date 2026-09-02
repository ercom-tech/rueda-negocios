# Saneo de los parámetros que llegan por URL y se usan para consultar.
#
# Vive aquí, y no como método privado de quien lo necesita, porque el defecto
# que cubre ya se pagó dos veces: un `?user_id[]=1` llega como **arreglo** y un
# `?user_id[x]=1` como `ActionController::Parameters`, y sobre cualquiera de
# los dos un `to_i` levanta `NoMethodError` — o sea la pantalla de error de
# Rails en la laptop del evento. `OrdersFilter` lo resolvió en su momento y el
# reporte de productos, escrito después, volvió a caer (9ª auditoría).
module ParamSanitizing
  module_function

  # Un id de catálogo: entero positivo, o nil. Rechaza arreglos, hashes y
  # cadenas que no sean números — nunca levanta.
  def id(value)
    return nil unless value.is_a?(String) || value.is_a?(Integer)

    number = Integer(value, exception: false)
    number if number&.positive?
  end

  # Número de página para Pagy. Un `?page[]=2` hace que Pagy levante
  # `Pagy::VariableError`, que NO es `Pagy::OverflowError` y por tanto el
  # `rescue_from` del controlador no atrapa.
  def page(value)
    id(value) || 1
  end

  # Texto libre: recortado, o nil.
  def text(value)
    value.strip.presence if value.is_a?(String)
  end
end
