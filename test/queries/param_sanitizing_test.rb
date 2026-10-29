require "test_helper"

class ParamSanitizingTest < ActiveSupport::TestCase
  # Un id que no cabe en un bigint pasaba el saneo y reventaba después, al
  # armar SQL a mano (`IntegerOutOf64BitRange`): 500 en el reporte (12ª).
  test "un id que no cabe en un bigint se descarta" do
    assert_nil ParamSanitizing.id("99999999999999999999")
    assert_nil ParamSanitizing.id((2**63).to_s)
    assert_equal (2**63) - 1, ParamSanitizing.id(((2**63) - 1).to_s)
    assert_equal 5, ParamSanitizing.id("5")
  end

  # Un "010" era 8 (octal) para el saneo y 10 para ActiveRecord (17ª).
  test "un id se lee en base 10" do
    assert_equal 10, ParamSanitizing.id("010")
    assert_nil ParamSanitizing.id("0x1f")
    assert_nil ParamSanitizing.id("0b11")
    assert_equal 7, ParamSanitizing.id(7)
  end

  test "page_size solo deja pasar uno de los tamaños permitidos" do
    sizes = [ 25, 50, 100 ]
    assert_equal 50, ParamSanitizing.page_size("50", sizes)
    assert_equal 25, ParamSanitizing.page_size("5000", sizes)
    assert_equal 25, ParamSanitizing.page_size([ "50" ], sizes)
    assert_equal 25, ParamSanitizing.page_size({ "x" => "50" }, sizes)
    assert_equal 25, ParamSanitizing.page_size(nil, sizes)
  end
end
