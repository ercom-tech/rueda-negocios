require "test_helper"

class ClientTest < ActiveSupport::TestCase
  # `Client.search` vivía como método privado de OrdersController. Se movió al
  # modelo —espejo de `Product.search`— porque "buscar cliente" tiene una
  # relevancia propia que las demás pantallas necesitan reusar: como método del
  # controlador, la siguiente lo copia y a partir de ahí buscar un cliente
  # significa dos cosas distintas según dónde estés. De paso, la lógica queda
  # al alcance de las pruebas de modelo, que es donde se puede fijar.

  setup do
    @exacto   = Client.create!(erp_client_key: "FERRE1", name: "FERRETERIA DEL NORTE",
                               commercial_name: "FERREMAQ")
    @contiene = Client.create!(erp_client_key: "ABC001", name: "DISTRIBUIDORA FERREMAQ SUR",
                               commercial_name: "DISTRISUR")
    @otro     = Client.create!(erp_client_key: "XYZ999", name: "TORNILLOS DEL GOLFO",
                               commercial_name: "TORGOLFO")
  end

  test "encuentra por clave, por nombre y por nombre comercial" do
    assert_includes Client.search("FERRE1"), @exacto
    assert_includes Client.search("DEL NORTE"), @exacto
    assert_includes Client.search("TORGOLFO"), @otro
  end

  test "no distingue mayúsculas" do
    assert_includes Client.search("ferremaq"), @exacto
  end

  # La relevancia es la razón de ser del scope: quien teclea "FERREMAQ" espera
  # primero al que SE LLAMA así, no al que lo lleva a media razón social.
  test "primero los que empiezan con lo tecleado" do
    resultados = Client.search("FERREMAQ").to_a

    assert_equal [ @exacto, @contiene ], resultados
  end

  test "una búsqueda vacía no devuelve nada" do
    assert_empty Client.search("")
    assert_empty Client.search("   ")
    assert_empty Client.search(nil)
  end

  # Los comodines de SQL se escapan: sin esto un "%" tecleado traería todo.
  test "los comodines tecleados se tratan como texto" do
    assert_empty Client.search("%")
    assert_empty Client.search("_")
  end

  test "precarga el vendedor: el desplegable lo muestra en cada renglón" do
    assert_predicate Client.search("FERRE").includes_values, :any?
  end
end
