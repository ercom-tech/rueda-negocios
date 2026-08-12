require "test_helper"
require "webmock/minitest"

module Sync
  class ApiClientTest < ActiveSupport::TestCase
    API = "http://api.test".freeze

    test "una respuesta 2xx no-JSON se envuelve en ApiClient::Error (no revienta el panel)" do
      stub_request(:get, "#{API}/ruedas").to_return(status: 200, body: "<html>gateway</html>")

      error = assert_raises(ApiClient::Error) { ApiClient.new(API).list_rounds }
      assert_match(/no es JSON/, error.message)
    end

    test "un HTTP no exitoso se reporta como ApiClient::Error con el código" do
      stub_request(:get, "#{API}/ruedas").to_return(status: 500, body: "boom")

      error = assert_raises(ApiClient::Error) { ApiClient.new(API).list_rounds }
      assert_match(/HTTP 500/, error.message)
    end

    test "un error con mensaje de negocio de la API llega con ese mensaje" do
      # El 404 de rueda inexistente trae {error, message}: "HTTP 404" a secas
      # mandaba al operador a revisar la red cuando lo roto era el número de
      # rueda tecleado. (5ª auditoría.)
      stub_request(:get, "#{API}/ruedas/99/export")
        .to_return(status: 404,
                   body: { error: "not_found",
                           message: "No hay ninguna rueda 99 vigente en el ERP." }.to_json)

      error = assert_raises(ApiClient::Error) { ApiClient.new(API).fetch_export(99) }
      assert_match(/No hay ninguna rueda 99 vigente/, error.message)
    end
  end
end
