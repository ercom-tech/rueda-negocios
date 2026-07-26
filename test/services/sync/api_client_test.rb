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
  end
end
