require "application_system_test_case"

# Un pedido capturado sigue siendo editable, y el capturista puede tenerlo
# abierto mientras el servidor lo transmite. El siguiente cambio respondía un
# 403 vacío: la cantidad regresaba sola y el modal de promoción se cerraba,
# sin decir por qué (16ª auditoría). Ahora vuelve a la captura con el aviso,
# ya en solo lectura.
class TransmittedMeanwhileTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_601, username: "cap_trx", password: "secret123",
                          role: "capturista", active: true)
    round  = BusinessRound.create!(erp_round_id: 970_601, name: "Rueda trx", active: true)
    Setting.instance.update!(selected_round_erp_id: 970_601, selected_round_name: "Rueda trx")
    supplier = Supplier.create!(erp_supplier_id: 970_601, name: "MAKITA")
    BusinessRoundPerson.create!(business_round: round, user: @user, supplier: supplier, position: 1)
    client = Client.create!(erp_client_key: "TRX01", name: "CLIENTE TRX")
    client.receipt_profiles.create!(name: "REMISION")

    drill = Product.create!(erp_product_id: 970_601, description: "TALADRO TRX", unit: "PZA", max_discount: 9)
    Price.create!(product: drill, credit_wholesale_price: 1000, tax_rate: 16)
    ProductSupplier.create!(product: drill, supplier: supplier)
    promo = Promotion.create!(erp_promotion_id: 970_601, code: "TRX", name: "MAKITA - TRX",
                              starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    promo.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CM", unit: "MXN",
                                  quantity_from: 1000, quantity_to: 0, discount_percent: 14)
    promo.promotion_products.create!(product: drill, discount_percent: 0)

    @order = Order.create!(user: @user, business_round: round, client: client, kind: "remission",
                           client_receipt_profile: client.receipt_profiles.first)
    @item = @order.order_items.create!(drill.to_order_item_attributes.merge(position: 1, quantity: 2,
                                                                             discount_percent: 0))
    @order.capture!
  end

  def transmit_meanwhile
    @order.update_columns(status: "transmitted", erp_folio: "1A0001", transmitted_at: Time.current)
  end

  test "corregir una cantidad de un pedido ya transmitido lo dice y deja la captura en solo lectura" do
    sign_in @user
    visit order_path(@order)
    transmit_meanwhile

    field = find("input[aria-label^='Cantidad']")
    field.fill_in(with: "5")
    find("h1").click # sale del campo: el blur envía

    assert_text "Este pedido ya se transmitió al ERP: ya no se puede cambiar. Así quedó."
    assert_text "Transmitido"
    assert_no_selector "input[aria-label^='Cantidad']"
    assert_equal 2, @item.reload.quantity
  end

  test "aplicar una promoción a un pedido ya transmitido lo dice en vez de cerrar el modal callado" do
    sign_in @user
    visit order_path(@order)
    first("[aria-label^='Promoción MAKITA']").click
    within("[role=dialog][aria-label^='Promoción MAKITA']") { assert_button "Aplicar promoción" }
    transmit_meanwhile

    within("[role=dialog][aria-label^='Promoción MAKITA']") { click_button "Aplicar promoción" }

    assert_text "Este pedido ya se transmitió al ERP: ya no se puede cambiar. Así quedó."
    assert_text "Transmitido"
    assert_nil @item.reload.promotion_id
  end
end
