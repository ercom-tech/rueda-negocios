require "test_helper"

# El proveedor se muestra por su NOMBRE COMERCIAL en toda pantalla, y por su
# razón social solo si el catálogo no trae el comercial (homologado el
# 2026-09-29). La ventanita del producto nuevo ya decía "STIHL" mientras la
# barra de arriba decía "STIHL S.A. DE C.V." en la misma pantalla.
class SupplierDisplayNameTest < ActionDispatch::IntegrationTest
  setup do
    @round = BusinessRound.create!(erp_round_id: 966_201, name: "Rueda nombres", active: true)
    Setting.instance.update!(selected_round_erp_id: 966_201, selected_round_name: "Rueda nombres")
    @stihl = Supplier.create!(erp_supplier_id: 966_201, name: "ANDREAS STIHL, S.A. DE C.V.", commercial_name: "STIHL")
    @apex  = Supplier.create!(erp_supplier_id: 966_202, name: "APEX TOOL GROUP MEXICO S DE RL", commercial_name: "APEX")
    @user  = User.create!(erp_person_id: 966_201, username: "cap_nombres", password: "secret123",
                          role: "capturista", active: true)
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @stihl, position: 1)
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @apex, position: 2)
    login_as "cap_nombres"
  end

  test "la píldora de la barra superior usa el nombre comercial, en orden alfabético" do
    get root_path

    labels = response.body.scan(/role="option"[^>]*data-label="([^"]+)"/).flatten
    assert_includes labels, "STIHL"
    assert_operator labels.index("APEX"), :<, labels.index("STIHL"), "APEX antes que STIHL"
    assert_no_match(/ANDREAS STIHL, S\.A\. DE C\.V\./, response.body)
  end

  test "con un solo proveedor, la píldora estática también" do
    BusinessRoundPerson.where(supplier: @apex).delete_all

    get root_path

    assert_match(/Proveedor: <span class="font-semibold">STIHL<\/span>/, response.body)
  end

  test "los filtros de los reportes usan el nombre comercial" do
    get products_report_path
    assert_match(/data-label="STIHL"/, response.body)
    assert_no_match(/data-label="ANDREAS STIHL/, response.body)

    get captured_orders_report_path
    assert_match(/data-label="STIHL"/, response.body)
    assert_no_match(/data-label="ANDREAS STIHL/, response.body)
  end

  test "el aviso de importes filtrados nombra al proveedor por su nombre comercial" do
    assert_equal "Importes de las partidas de STIHL", OrdersFilter.new(supplier_id: @stihl.id).items_label
  end

  test "el archivo del reporte de productos se nombra con el nombre comercial" do
    get products_report_path(supplier_id: @stihl.id, format: :csv)

    assert_match(/filename="productos-stihl-\d{4}-\d{2}-\d{2}\.csv"/, response.headers["Content-Disposition"])
  end

  # Sin nombre comercial en el catálogo, la razón social: un proveedor no puede
  # quedarse sin nombre en pantalla.
  test "sin nombre comercial se usa la razón social" do
    @stihl.update!(commercial_name: nil)

    get root_path

    assert_match(/data-label="ANDREAS STIHL, S\.A\. DE C\.V\."/, response.body)
  end
end
