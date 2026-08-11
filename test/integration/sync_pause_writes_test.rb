require "test_helper"

# Mientras corre un sync, la captura se pausa.
#
# Un mismo mecanismo para dos fallas distintas:
#
# - **Obtener información** vacía el catálogo dentro de su transacción; un
#   INSERT concurrente con FK a un cliente o un producto se quedaba esperando
#   el lock y luego reventaba con violación de llave foránea. El capturista
#   veía la pantalla de error del sistema y no sabía si su pedido existía.
# - **Transmitir pedidos** arma el payload, hace el POST y hasta después marca
#   `transmitted`. Un pedido `captured` sigue siendo editable por su dueño, así
#   que un cambio en esa ventana dejaba al ERP con la versión vieja y a la
#   pantalla con la nueva, sin aviso en ningún lado.
class SyncPauseWritesTest < ActionDispatch::IntegrationTest
  setup do
    @user     = User.create!(erp_person_id: 950_001, username: "cap950s", password: "secret123",
                             role: "capturista", active: true)
    @round    = BusinessRound.create!(erp_round_id: 950_001, name: "Rueda 950s", active: true)
    supplier  = Supplier.create!(erp_supplier_id: 950_001, name: "PROVEEDOR 950s")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: supplier)
    @client   = Client.create!(erp_client_key: "C950S", name: "Cliente 950s")
    @order    = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")
    @item     = @order.order_items.create!(position: 1, quantity: 1, unit_price: 100,
                                           tax_rate: 16, discount_percent: 0)
    post login_path, params: { username: "cap950s", password: "secret123" }
  end

  def sync_running!(kind = "down")
    SyncRun.create!(kind: kind, started_at: Time.current)
  end

  test "con un sync en curso no se puede editar una partida" do
    sync_running!

    patch order_order_item_path(@order, @item), params: { order_item: { quantity: 7 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/Se está actualizando la información/, response.body)
    assert_equal 1, @item.reload.quantity, "no debe escribir nada"
  end

  test "con un sync en curso no se puede quitar una partida" do
    sync_running!

    assert_no_difference "OrderItem.count" do
      delete order_order_item_path(@order, @item),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "con un sync en curso no se puede finalizar un pedido" do
    sync_running!("up")

    post capture_order_path(@order)

    assert_redirected_to root_path
    assert_match(/Se está actualizando la información/, flash[:alert])
    assert @order.reload.draft?, "el pedido no debe finalizarse a media transmisión"
  end

  test "con un sync en curso no se puede crear un pedido" do
    sync_running!

    assert_no_difference "Order.count" do
      post orders_path, params: { order: { client_id: @client.id, kind: "remission" } }
    end
  end

  # Leer sigue disponible: el operador revisa pedidos mientras transmite, y
  # bloquear la lectura sería un callejón sin salida durante el sync.
  test "leer un pedido sigue disponible durante un sync" do
    sync_running!

    get order_path(@order)
    assert_response :success
  end

  test "sin sync en curso todo se escribe normal" do
    patch order_order_item_path(@order, @item), params: { order_item: { quantity: 7 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal 7, @item.reload.quantity
  end

  # Una corrida ya cerrada no bloquea: solo las vivas.
  test "una corrida terminada no pausa la captura" do
    SyncRun.create!(kind: "down", started_at: 1.hour.ago).finish!(status: :completed)

    patch order_order_item_path(@order, @item), params: { order_item: { quantity: 7 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal 7, @item.reload.quantity
  end
end
