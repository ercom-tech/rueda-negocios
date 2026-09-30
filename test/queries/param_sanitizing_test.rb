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
end
