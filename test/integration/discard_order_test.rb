require "test_helper"

# El descarte dice la verdad: sobre un pedido ya transmitido, el destroy se
# omitía en silencio y el flash confirmaba "Pedido descartado." — el
# capturista creía cancelada una venta que el ERP iba a surtir (6ª auditoría,
# ALTA). La pantalla vieja conserva el botón, así que la rama es real.
class DiscardOrderTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(erp_person_id: 967_001, username: "cap_disc", password: "secret123",
                          role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 967_001, name: "R", active: true)
    @client = Client.create!(erp_client_key: "DSC01", name: "C")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission",
                            status: "transmitted", erp_folio: "1A0001", local_folio: "RN-000967")
    login_as "cap_disc"
  end

  # --- Con una promoción aplicada ------------------------------------------
  # Las partidas de una promoción aplicada llevan un `before_destroy` con
  # `throw :abort` (7ª auditoría). `orders#destroy` llama a `order.destroy` sin
  # mirar el resultado, así que si el candado aborta, el pedido sobrevive y el
  # flash dice "Pedido descartado." igual — el mismo defecto que la 6ª
  # auditoría marcó como ALTA para los transmitidos, por otra puerta.

  def promoted_order!(status:)
    product = Product.create!(erp_product_id: 967_101, description: "MARTILLO DSC", max_discount: 50)
    Price.create!(product: product, credit_wholesale_price: 100, tax_rate: 16)
    promotion = Promotion.create!(erp_promotion_id: 967_101, code: "DSC01", name: "PROMO DSC",
                                  starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
    promotion.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CM", unit: "MXN",
                                      quantity_from: 1, quantity_to: 0, discount_percent: 10)
    promotion.promotion_products.create!(product: product, discount_percent: 0)

    order = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    order.order_items.create!(product: product, position: 1, quantity: 2, unit_price: 100,
                              discount_percent: 0, tax_rate: 16, code: "967101",
                              description: "MARTILLO DSC", unit: "PZA")
    Promotions::Group.new(order.reload, promotion).apply!
    order.reload.update!(status: status, local_folio: ("RN-000968" if status == "captured"))
    order
  end

  test "descartar un borrador con promoción aplicada lo borra de verdad" do
    order = promoted_order!(status: "draft")

    delete order_path(order)

    assert_not Order.exists?(order.id), "el pedido debe quedar borrado"
    assert_equal 0, OrderItem.where(order_id: order.id).count, "y sus partidas también"
    assert_match(/descartado/i, flash[:notice].to_s)
  end

  # El camino desde el reporte de pedidos capturados: el folio abre el mismo
  # orders#show, así que el descarte pasa por el mismo destroy, pero con el
  # pedido en `captured` — que sí es descartable (`editable?` solo excluye
  # transmitidos).
  test "descartar un capturado con promoción, llegando desde el reporte, lo borra" do
    order = promoted_order!(status: "captured")

    # Tal cual lo hace el reporte: el folio enlaza a order_path.
    get captured_orders_report_path
    assert_response :success

    delete order_path(order)

    assert_not Order.exists?(order.id), "el pedido debe quedar borrado"
    assert_equal 0, OrderItem.where(order_id: order.id).count
    assert_match(/descartado/i, flash[:notice].to_s)
  end

  test "descartar un pedido transmitido no lo borra y lo dice" do
    assert_no_difference "Order.count" do
      delete order_path(@order)
    end

    assert_redirected_to order_path(@order)
    assert_match(/ya se transmitió al ERP y no se puede descartar aquí/, flash[:alert])
    assert_no_match(/descartado/i, flash[:notice].to_s, "no debe confirmar un descarte que no ocurrió")
  end

  test "descartar un borrador sigue funcionando y confirmando" do
    draft = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")

    assert_difference "Order.count", -1 do
      delete order_path(draft)
    end
    assert_equal "Pedido descartado.", flash[:notice]
  end
end
