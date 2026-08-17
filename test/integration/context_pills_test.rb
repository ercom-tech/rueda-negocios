require "test_helper"

# Pills de contexto del top bar: Proveedor y Marca solo aparecen si el
# capturista tiene membresías de ese tipo (0 → oculto, 1 → estático,
# varios → selector).
class ContextPillsTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 940, username: "cap940", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 940, name: "Rueda 940", active: true)
    @sup   = Supplier.create!(erp_supplier_id: 940, name: "PROVEEDOR 940")
    @brand = Brand.create!(erp_brand_id: 940, name: "MARCA 940")
    login_as "cap940"
  end

  def membership!(position:, supplier: nil, brand: nil)
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: position,
                                supplier: supplier, brand: brand)
  end

  test "sin membresías no se muestra ningún pill" do
    get root_path
    assert_response :success
    assert_no_match(/Proveedor:/, response.body)
    assert_no_match(/Marca:/, response.body)
  end

  test "solo proveedor: pill de proveedor estático, sin pill de marca" do
    membership!(position: 1, supplier: @sup)

    get root_path
    assert_match(/Proveedor:/, response.body)
    assert_match(/PROVEEDOR 940/, response.body)
    assert_no_match(/Marca:/, response.body)
  end

  test "solo marca: pill de marca estático, sin pill de proveedor" do
    membership!(position: 1, brand: @brand)

    get root_path
    assert_match(/Marca:/, response.body)
    assert_match(/MARCA 940/, response.body)
    assert_no_match(/Proveedor:/, response.body)
  end

  test "varias marcas: selector, y el PATCH cambia la marca activa" do
    another = Brand.create!(erp_brand_id: 941, name: "MARCA 941")
    membership!(position: 1, supplier: @sup, brand: @brand)
    membership!(position: 2, brand: another)

    get root_path
    assert_select "form[action=?]", active_brand_path

    patch active_brand_path, params: { brand_id: another.id }
    follow_redirect!
    # La marca activa elegida persiste en la sesión y se refleja en el pill.
    assert_select "input[name=brand_id][value=?]", another.id.to_s

    # Un id ajeno no se acepta (queda la elección previa).
    intrusa = Brand.create!(erp_brand_id: 999, name: "MARCA AJENA")
    patch active_brand_path, params: { brand_id: intrusa.id }
    follow_redirect!
    assert_select "input[name=brand_id][value=?]", another.id.to_s
  end
end
