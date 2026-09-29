# Cómo se juntan los textos que ve el usuario.
#
# Existe porque la herramienta de Rails para esto, `to_sentence`, aplica las
# reglas del INGLÉS —igual que `pluralize`— y la app no tiene traducción de los
# conectores: juntaba con " and ". Así salía en pantalla "Escribe el precio
# unitario (mayor a cero). and Escribe la descripción del producto." (visto por
# el usuario, 2026-09-29). Un solo lugar para que la siguiente pantalla no
# vuelva a caer en `to_sentence`.
module SpanishText
  module_function

  # Una lista de nombres: "A", "A y B", "A, B y C".
  #
  # "y" se vuelve "e" ante una palabra que suena a /i/ ("TALADRO e IMPACTO",
  # "LIJA e HIDROLAVADORA"), pero no ante un diptongo ("CLAVO y HIERRO"):
  # es la regla de la RAE, y los nombres del catálogo caen en los dos casos.
  def list(items)
    items = items.compact.map(&:to_s)
    return items.first.to_s if items.size <= 1

    "#{items[0...-1].join(', ')} #{conjunction_before(items.last)} #{items.last}"
  end

  # Mensajes que ya son oraciones completas, con su punto (los de validación
  # de las partidas). Se juntan como oraciones, no como lista: aun con el
  # conector en español, "…(mayor a cero). y Escribe…" no se lee bien.
  def sentences(messages)
    messages.map { |message| message.to_s.strip }.reject(&:empty?).join(" ")
  end

  def conjunction_before(word)
    word.match?(/\A[hH]?[iIíÍ](?![aeiouáéíóúAEIOUÁÉÍÓÚ])/) ? "e" : "y"
  end
end
