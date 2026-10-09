require "test_helper"

class PricesHelperTest < ActionView::TestCase
  test "dice hacia dónde se mueven los precios, con concordancia" do
    assert_equal "2,900 suben · 406 bajan", price_directions_label(up: 2900, down: 406)
    assert_equal "1 sube · 1 baja", price_directions_label(up: 1, down: 1)
    assert_equal "3 suben", price_directions_label(up: 3, down: 0), "sin el lado en cero"
    assert_equal "Ninguno", price_directions_label(up: 0, down: 0)
  end

  test "desglosa los motivos: los dos más frecuentes y el resto como N más" do
    assert_equal "17 sin precio · 3 fuera de la rueda",
                 rejected_kinds_label([ [ :no_price, 17 ], [ :not_in_round, 3 ] ])
    assert_equal "2 códigos inválidos · 1 repetido con otro precio · 4 más",
                 rejected_kinds_label([ [ :invalid_code, 2 ], [ :conflict, 1 ], [ :generic, 3 ], [ :no_price, 1 ] ])
    assert_equal "Ninguno", rejected_kinds_label([])
  end
end
