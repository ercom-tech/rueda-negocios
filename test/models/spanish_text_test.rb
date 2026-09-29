require "test_helper"

# Cómo se juntan los textos en pantalla. `to_sentence` de Rails junta con
# " and " (reglas del inglés), y así llegó a la pantalla de captura.
class SpanishTextTest < ActiveSupport::TestCase
  test "una lista se junta con comas y la y del español" do
    assert_equal "", SpanishText.list([])
    assert_equal "TALADRO", SpanishText.list([ "TALADRO" ])
    assert_equal "TALADRO y BROCA", SpanishText.list(%w[TALADRO BROCA])
    assert_equal "TALADRO, BROCA y DISCO", SpanishText.list(%w[TALADRO BROCA DISCO])
  end

  # Regla de la RAE: "e" ante el sonido /i/, "y" ante diptongo.
  test "la y se vuelve e ante una palabra que suena a i" do
    assert_equal "TALADRO e IMPACTO", SpanishText.list(%w[TALADRO IMPACTO])
    assert_equal "LIJA e HIDROLAVADORA", SpanishText.list(%w[LIJA HIDROLAVADORA])
    assert_equal "CLAVO y HIERRO", SpanishText.list(%w[CLAVO HIERRO])
    assert_equal "BROCA y YESO", SpanishText.list(%w[BROCA YESO])
  end

  test "las oraciones se juntan como oraciones, no como lista" do
    assert_equal "Escribe el precio unitario (mayor a cero). Escribe la descripción del producto.",
                 SpanishText.sentences([ "Escribe el precio unitario (mayor a cero).",
                                         "Escribe la descripción del producto." ])
    assert_equal "Una sola.", SpanishText.sentences([ "Una sola." ])
  end
end
