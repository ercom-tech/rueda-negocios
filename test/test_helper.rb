ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  # Login compartido: había tres copias con dos nombres (`login`, `sign_in`) y
  # ~13 POST inline con la misma contraseña. `session:` permite usarlo con
  # `open_session` (sesiones múltiples, p. ej. la prueba de sesión única).
  def login_as(username, password: "secret123", session: self)
    session.post "/login", params: { username: username, password: password }
  end
end
