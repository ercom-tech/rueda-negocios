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
