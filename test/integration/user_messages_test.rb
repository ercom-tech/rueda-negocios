require "test_helper"

# Que el usuario pueda LEER lo que el sistema le dice, y salir de donde quedó.
#
# El contexto es la vara: salón lleno, tablet, prisa, sin internet. Un aviso
# que se va antes de leerse o una pantalla sin salida no tienen a quién
# preguntarle.
class UserMessagesTest < ActionDispatch::IntegrationTest
  setup do
    @user   = User.create!(erp_person_id: 930_001, username: "cap930", password: "secret123",
                           role: "capturista", active: true)
    @round  = BusinessRound.create!(erp_round_id: 930_001, name: "Rueda 930", active: true)
    @client = Client.create!(erp_client_key: "C930", name: "Cliente 930")
    login_as "cap930"
  end

  # Por el flash viajan las instrucciones de dos pasos de las guardas del sync
  # —unas 30 palabras—, y aparecían arriba al centro mientras el operador mira
  # la card que acaba de picar. A los 8 segundos ya no estaban, y no había
  # forma de recuperarlas.
  test "un aviso de error no se auto-cierra" do
    post orders_path, params: { order: { client_id: @client.id, kind: "regalo" } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]" do
      assert_select "[data-flash-delay-value=?]", "0"
    end
  end

  test "las confirmaciones sí siguen desapareciendo solas" do
    get root_path

    assert_select "[role=status][data-controller=flash]" do |elements|
      assert_nil elements.first["data-flash-delay-value"],
                 "un notice usa el tiempo por omisión"
    end
  end

  # Sin nombre accesible, un lector de pantalla anuncia los cuatro combos del
  # encabezado igual —"— Selecciona —, listbox"— y el aviso "Faltan datos
  # obligatorios: Uso de CFDI" no se puede emparejar con ninguno.
  test "los combos del encabezado se anuncian con su propio nombre" do
    ClientTaxProfile.create!(client: @client, rfc: "AAA010101AAA", business_name: "CLIENTE 930 SA")
    ClientBranch.create!(client: @client, erp_branch_id: 1, name: "MATRIZ")
    CfdiUse.create!(code: "G01", description: "ADQUISICIÓN DE MERCANCÍAS")

    get new_order_path(client_key: @client.erp_client_key)

    assert_response :success
    [ "Uso de CFDI", "Nombre o razón social (RFC)", "Dirección de entrega" ].each do |name|
      assert_select "button[aria-label=?]", name
    end
  end

  # Las de Rails están en inglés, sin una sola liga y pidiendo "revisar los
  # logs". El botón Atrás tras descartar un pedido llega ahí, y sin internet no
  # hay a quién preguntarle ni la dirección del servidor a la mano.
  test "las pantallas de error hablan español y dejan salida al menú" do
    %w[400 404 422 500].each do |code|
      page = Rails.public_path.join("#{code}.html").read

      assert_match(/lang="es"/, page, "#{code}.html debe estar en español")
      assert_match(%r{href="/"}, page, "#{code}.html necesita una salida al menú")
      assert_match(/Ir al menú/, page)
      assert_no_match(/check the logs/i, page, "#{code}.html no debe hablar de logs")
    end
  end
end
