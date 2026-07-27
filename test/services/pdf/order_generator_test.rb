require "test_helper"

module Pdf
  class OrderGeneratorTest < ActiveSupport::TestCase
    # amount_in_words no depende del estado del pedido: se prueba directo.
    def words(total)
      OrderGenerator.allocate.send(:amount_in_words, total)
    end

    test "un total a precisión completa se cuantiza antes del importe en letra" do
      # Sin round(2), 100.999 daba "CIEN PESOS 100/100 M.N."
      assert_equal "CIENTO UN PESOS 00/100 M.N.", words(BigDecimal("100.999"))
    end

    test "centavos normales" do
      assert_equal "CUATROCIENTOS SETENTA Y UN PESOS 08/100 M.N.", words(BigDecimal("471.08"))
      assert_equal "CERO PESOS 50/100 M.N.", words(BigDecimal("0.50"))
    end

    test "miles de millones no truenan (recursión en millones)" do
      assert_equal "MIL MILLONES PESOS 00/100 M.N.", words(BigDecimal("1000000000"))
      assert_includes words(BigDecimal("2500000000.75")), "DOS MIL QUINIENTOS MILLONES"
    end
  end
end
