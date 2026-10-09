# Cambiar precios desde un archivo (panel del servidor, 2026-10-08): lector,
# revisión, resguardo temporal y exportaciones viven bajo este espacio.
module PriceList
  # La variación como se MUESTRA ("+5.1%", "-73.0%"), igual en la pantalla de
  # revisión, en su CSV y en el de precios cargados. Antes cada uno la
  # formateaba —y el de precios cargados la calculaba— por su cuenta, y un
  # ajuste en uno dejaba de coincidir con los otros (13ª auditoría). nil
  # cuando no hay contra qué comparar.
  def self.variation_label(fraction)
    format("%+.1f%%", fraction * 100) unless fraction.nil?
  end
end
