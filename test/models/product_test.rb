require "test_helper"

class ProductTest < ActiveSupport::TestCase
  setup do
    @product = Product.create!(erp_product_id: 17768, description: "MARTILLO PRUEBA",
                               model: "M1", part_number: "0ABC-1")
  end

  test "erp_code presenta el código a 6 dígitos, como lo muestra el ERP" do
    assert_equal "017768", @product.erp_code
  end

  test "la búsqueda encuentra por código padded, sin pad y parcial" do
    assert_includes Product.search("017768"), @product
    assert_includes Product.search("17768"), @product
    assert_includes Product.search("0177"), @product
  end

  test "un código padded completo es exacto: no arrastra coincidencias engañosas" do
    objetivo = Product.create!(erp_product_id: 81, description: "PRODUCTO 81")
    ruido    = [ Product.create!(erp_product_id: 3381, description: "RUIDO A"),
                Product.create!(erp_product_id: 4817, description: "RUIDO B"),
                Product.create!(erp_product_id: 8681, description: "RUIDO C") ]

    resultado = Product.search("000081")
    assert_includes resultado, objetivo
    ruido.each { |r| assert_not_includes resultado, r }
  end

  test "el N/P con cero inicial se sigue encontrando tal cual" do
    assert_includes Product.search("0ABC"), @product
  end

  test "una consulta de puros ceros no degenera en match-todo" do
    assert_empty Product.search("000000")
  end

  test "el snapshot de partida guarda el código a 6 dígitos" do
    assert_equal "017768", @product.to_order_item_attributes[:code]
  end

  # El nivel que vende la rueda es CRÉDITO MAYOREO (decisión FECEGO
  # 2026-08-17), no el público — que solo queda de referencia.
  test "el snapshot de partida cobra el precio crédito mayoreo" do
    Price.create!(product: @product, public_price: 471.08, wholesale_price: 407.82,
                  credit_wholesale_price: 429.44, tax_rate: 16)

    assert_equal 429.44, @product.to_order_item_attributes[:unit_price]
  end

  test "generic? distingue al 999999 del resto" do
    assert Product.new(erp_product_id: Product::GENERIC_ERP_ID).generic?
    assert_not @product.generic?
  end

  # Sin fallback a otro nivel: un crédito mayoreo en $0 en el ERP deja el
  # producto invendible con aviso ("producto sin precio") — el dato se
  # corrige allá, que es su dueño.
  test "sin precio crédito mayoreo el snapshot queda en cero (invendible)" do
    Price.create!(product: @product, public_price: 471.08, wholesale_price: 407.82,
                  credit_wholesale_price: 0, tax_rate: 16)

    assert_equal 0, @product.to_order_item_attributes[:unit_price]
  end
end
