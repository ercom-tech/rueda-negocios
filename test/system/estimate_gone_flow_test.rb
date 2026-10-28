require "application_system_test_case"

# Una cotización que desaparece con su pantalla abierta (15ª auditoría).
# "Obtener información" y "Cerrar rueda" borran las cotizaciones sin que nada
# lo impida —un borrador de pedido, en cambio, bloquea las dos—, así que hay
# capturistas con la captura abierta de algo que ya no existe. Estas pruebas
# cubren las puertas que `order_gone` no alcanzaba: un modal por frame y los
# buscadores, que piden con fetch y no navegan.
class EstimateGoneFlowTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_501, username: "cap_gone", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_501, name: "Rueda gone", active: true)
    Setting.instance.update!(selected_round_erp_id: 970_501, selected_round_name: "Rueda gone")
    @supplier = Supplier.create!(erp_supplier_id: 970_501, name: "MAKITA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @supplier, position: 1)
    @client = Client.create!(erp_client_key: "GONE01", name: "CLIENTE GONE")
    @client.receipt_profiles.create!(name: "REMISION")

    @drill = Product.create!(erp_product_id: 970_501, description: "TALADRO GONE", unit: "PZA", max_discount: 9)
    Price.create!(product: @drill, credit_wholesale_price: 1000, tax_rate: 16)
    ProductSupplier.create!(product: @drill, supplier: @supplier)
    @promo = Promotion.create!(erp_promotion_id: 970_501, code: "GONE", name: "MAKITA - GONE",
                               starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    @promo.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CM", unit: "MXN",
                                   quantity_from: 1000, quantity_to: 0, discount_percent: 14)
    @promo.promotion_products.create!(product: @drill, discount_percent: 0)

    @estimate = Order.create!(user: @user, business_round: @round, document: "estimate")
    @estimate.order_items.create!(@drill.to_order_item_attributes.merge(position: 1, quantity: 1, discount_percent: 0))
  end

  # El modal de promoción carga por frame; sobre una cotización borrada el
  # servidor redirige al menú con el aviso, y sin manejador Turbo escribía
  # "Content missing", en inglés, dentro del diálogo.
  test "el modal de promoción de una cotización borrada lleva al menú con el aviso" do
    sign_in @user
    visit order_path(@estimate)
    Order.purge_estimates!

    first("[aria-label^='Promoción MAKITA']").click

    assert_text "ya no está en esta laptop"
    assert_current_path root_path
    assert_no_text "Content missing"
  end

  # Tras "Cerrar rueda", el capturista ya no tiene rueda y cualquier petición
  # lo manda al login. El buscador pide con fetch, que sigue la redirección:
  # la página de login entera se inyectaba dentro del panel de sugerencias.
  test "tras cerrar la rueda, el buscador de producto lleva al login en vez de meterlo en su panel" do
    sign_in @user
    visit order_path(@estimate)
    Sync::CloseRound.run!

    fill_in "Busca por código, nombre, modelo o No. de parte", with: "TALADRO"

    assert_current_path login_path
    # El aviso del servidor llega: se navegó con la respuesta ya recibida, que
    # trae el flash; volver a pedir la página lo habría perdido.
    assert_text "No hay rueda en curso en esta laptop"
    assert_selector "input[name=username]", count: 1
    assert_no_selector "#order-detail"
  end
end
