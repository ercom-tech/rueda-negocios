require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @round    = BusinessRound.create!(erp_round_id: 9401, name: "Rueda U", active: true)
    @user     = User.create!(erp_person_id: 9401, username: "cap_u", password: "x", role: "capturista")
    @supplier = Supplier.create!(erp_supplier_id: 9401, name: "Prov U")
    @brand    = Brand.create!(erp_brand_id: 9401, name: "Marca U")

    @by_supplier = Product.create!(erp_product_id: 94_011, description: "Del proveedor")
    ProductSupplier.create!(product: @by_supplier, supplier: @supplier)
    @by_brand  = Product.create!(erp_product_id: 94_012, description: "De la marca", brand: @brand)
    @outside   = Product.create!(erp_product_id: 94_013, description: "Ajeno")
  end

  test "el universo une productos de sus proveedores y de sus marcas" do
    BusinessRoundPerson.create!(business_round: @round, user: @user,
                                supplier: @supplier, brand: @brand, position: 1)

    universe = @user.product_universe(@round)

    assert_includes universe, @by_supplier
    assert_includes universe, @by_brand
    assert_not_includes universe, @outside
  end

  test "sin membresía y sin genérico en catálogo el universo es vacío" do
    assert_empty @user.product_universe(@round)
    assert_empty @user.product_universe(nil)
  end

  # El genérico 999999 (fuera de catálogo) es de todos — decisión FECEGO
  # 2026-08-17: incluso un capturista sin proveedor ni marca captura con él.
  test "sin membresía el universo trae solo el genérico" do
    generic = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "AJUSTE DE MERCANCIA")

    assert_equal [ generic ], @user.product_universe(@round).to_a
    assert_empty @user.product_universe(nil), "sin rueda no hay universo, ni genérico"
  end

  test "con membresía el universo también trae el genérico" do
    generic = Product.create!(erp_product_id: Product::GENERIC_ERP_ID, description: "AJUSTE DE MERCANCIA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @supplier, position: 1)

    universe = @user.product_universe(@round)
    assert_includes universe, @by_supplier
    assert_includes universe, generic
    assert_not_includes universe, @outside
  end

  test "el universo es buscable (encadena con Product.search)" do
    BusinessRoundPerson.create!(business_round: @round, user: @user,
                                supplier: @supplier, position: 1)

    assert_equal [ @by_supplier ], @user.product_universe(@round).search("proveedor").to_a
    assert_empty @user.product_universe(@round).search("ajeno")
  end
end
