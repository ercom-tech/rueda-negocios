require "test_helper"

# La tabla de partidas del paso 2 muestra la MÁS RECIENTE arriba
# (decisión del usuario 2026-09-02): al capturar un pedido largo, la partida
# recién agregada quedaba fuera de la pantalla.
#
# Es un cambio de VISTA solamente, y aquí se ata que siga siéndolo: el orden de
# `order_items` es también el que numera las partidas en el ERP, así que
# invertir la asociación mandaría el pedido al revés y los regalos apuntando a
# la partida equivocada.
class ItemsDisplayOrderTest < ActionDispatch::IntegrationTest
  setup do
    @user   = User.create!(erp_person_id: 975, username: "cap975", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 975, name: "Rueda 975", active: true)
    Setting.instance.update!(selected_round_erp_id: 975, selected_round_name: "Rueda 975")
    @sup    = Supplier.create!(erp_supplier_id: 975, name: "PROVEEDOR")
    BusinessRoundPerson.create!(business_round: @round, user: @user, supplier: @sup, position: 1)
    @client = Client.create!(erp_client_key: "C975", name: "Cliente")
    @order  = Order.create!(user: @user, business_round: @round, client: @client, kind: "remission")

    %w[UNO DOS TRES].each_with_index do |nombre, i|
      p = Product.create!(erp_product_id: 975_001 + i, description: nombre, max_discount: 50)
      Price.create!(product: p, credit_wholesale_price: 100, tax_rate: 16)
      ProductSupplier.create!(product: p, supplier: @sup)
      @order.order_items.create!(product: p, position: i + 1, quantity: 1, unit_price: 100,
                                 discount_percent: 0, tax_rate: 16, code: p.erp_code,
                                 description: nombre, unit: "PZA")
    end
    login_as "cap975"
  end

  test "la tabla muestra la partida más reciente arriba" do
    get order_path(@order)

    assert_response :success
    posiciones = %w[UNO DOS TRES].map { |n| response.body.index(">#{n}<") || response.body.index(n) }
    assert_operator posiciones[2], :<, posiciones[1], "TRES antes que DOS"
    assert_operator posiciones[1], :<, posiciones[0], "DOS antes que UNO"
  end

  # La columna "Consecutivo" muestra `item.position`, o sea el número real de
  # la partida: se ve 3, 2, 1 y no una renumeración de la vista.
  test "el consecutivo visible sigue siendo el de la partida" do
    get order_path(@order)

    # La segunda celda de cada fila es "Consecutivo" (la primera es el bote de
    # basura). Por selector y no por regex: la celda del CÓDIGO usa las mismas
    # clases y se colaba en la lista.
    consecutivos = css_select("tbody tr td:nth-child(2)").map { |td| td.text.strip }.first(3)
    assert_equal %w[3 2 1], consecutivos
  end

  # El candado: la asociación NO se tocó, así que todo lo que deriva el orden de
  # ella —el PDF y, sobre todo, el consecutivo que viaja al ERP— sigue igual.
  test "la asociación conserva el orden ascendente" do
    assert_equal %w[UNO DOS TRES], @order.reload.order_items.map(&:description)
    assert_equal [ 1, 2, 3 ], @order.order_items.map(&:position)
  end

  test "el PDF imprime las partidas en su orden natural" do
    generator = Pdf::OrderGenerator.new(@order.reload)
    generator.render

    impresas = generator.send(:printed_items).map { |i| i[:description] }

    assert_equal %w[UNO DOS TRES], impresas, "el papel del cliente va 1, 2, 3"
  end
end
