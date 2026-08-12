require "application_system_test_case"

# Lo que ve el capturista cuando intenta guardar durante un sync (la pausa).
#
# El defecto (5ª auditoría, confirmado con clics reales): la pausa respondía
# 200, así que `turbo:submit-end` llegaba con `success: true` y la palomita
# "Guardado ✓" salía JUNTO al aviso rojo de "vuelve a intentar" — y ganaba la
# palomita. Además el campo se quedaba con el valor tecleado (la BD con el
# viejo) y el siguiente blur ya no reenviaba porque el valor "no cambió".
class SyncPauseFeedbackTest < ApplicationSystemTestCase
  setup do
    @user  = User.create!(erp_person_id: 970_101, username: "cap_pause", password: "secret123",
                          role: "capturista", active: true)
    @round = BusinessRound.create!(erp_round_id: 970_101, name: "Rueda pausa", active: true)
    supplier = Supplier.create!(erp_supplier_id: 970_101, name: "PROVEEDOR PAUSA")
    BusinessRoundPerson.create!(business_round: @round, user: @user, position: 1, supplier: supplier)
    client = Client.create!(erp_client_key: "SYS02", name: "Cliente pausa")

    @order = Order.create!(user: @user, business_round: @round, client: client, kind: "remission")
    @item  = @order.order_items.create!(position: 1, quantity: 1, unit_price: 100,
                                        tax_rate: 0, discount_percent: 0,
                                        code: "97101", description: "MARTILLO PAUSA", unit: "PZA")
  end

  # Con `pid` del proceso vivo: el barrido que corre al cargar el menú del
  # servidor respeta corridas con dueño vivo, y esta debe seguir "corriendo"
  # durante toda la prueba.
  def sync_running!
    SyncRun.create!(kind: "up", started_at: Time.current, pid: Process.pid)
  end

  test "editar observaciones durante un sync avisa sin palomita" do
    sign_in @user
    visit order_path(@order)

    sync_running!
    # Por placeholder: Capybara no localiza por aria-label sin configuración.
    fill_in "Observaciones", with: "ENTREGAR EL VIERNES"
    find("body").click # blur → change → submit

    assert_text "Se está actualizando la información"
    # La palomita vive en el DOM siempre (overlay con opacity-0): lo que se
    # afirma es que NO se hizo visible.
    assert_selector "[data-form-submit-target='status'].opacity-0", visible: :all
    assert_nil @order.reload.observations, "no debe escribir nada durante el sync"
  end

  test "una cantidad editada durante un sync revierte al valor guardado" do
    sign_in @user
    visit order_path(@order)

    sync_running!
    quantity = "quantity_order_item_#{@item.id}"
    fill_in quantity, with: "7"
    find("body").click # blur → submitIfChanged

    assert_text "Se está actualizando la información"
    assert_field quantity, with: "1"
    assert_equal 1, @item.reload.quantity, "no debe escribir nada durante el sync"
  end
end
