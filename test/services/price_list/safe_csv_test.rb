require "test_helper"

module PriceList
  class SafeCsvTest < ActiveSupport::TestCase
    test "neutraliza el texto que Excel ejecutaría como fórmula" do
      [ "=HYPERLINK(\"http://x\")", "+1", "-2", "@SUM(A1)", "\tx", "\rx" ].each do |value|
        assert_equal "'#{value}", SafeCsv.text(value), value.inspect
      end
    end

    test "deja igual el texto normal, los números y el vacío" do
      [ "MOTOSIERRA", "003021", "Lista Stihl.xlsx", 6900 ].each do |value|
        assert_equal value, SafeCsv.text(value), value.inspect
      end
      assert_nil SafeCsv.text(nil)
    end

    # De punta a punta: un código malicioso del archivo del proveedor, que la
    # revisión rechaza y devuelve en su CSV.
    test "el CSV de la revisión no devuelve una fórmula activa" do
      BusinessRound.create!(erp_round_id: 9601, name: "Rueda SC", active: true)
      problem = Reader::Problem.new(line: 2, code_text: "=HYPERLINK(\"http://x\")", reason: "x", kind: :invalid_code)
      review = Review.new(Struct.new(:rows, :problems).new([], [ problem ]))

      row = CSV.parse(ReviewExport.csv(review).delete_prefix("﻿"))[1]
      assert_equal "'=HYPERLINK(\"http://x\")", row[1]
    end
  end
end
