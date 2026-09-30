require "test_helper"
require "rake"

# `rake evidence:export`: arma, desde un respaldo restaurado de la laptop, la
# evidencia de los pedidos transmitidos para que rueda-api la importe al ERP
# (Oaxaca se transmitió antes de que existiera `vta_pedido_rueda`).
class EvidenceRakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task.clear
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/evidence", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)

    user   = User.create!(erp_person_id: 90126, username: "philips2", password: "x", role: "capturista",
                          name: "PROVEEDOR PHILIPS 2")
    round  = BusinessRound.create!(erp_round_id: 3, name: "Oaxaca", active: true)
    client = Client.create!(erp_client_key: "CRGAAL", name: "Cliente")
    @sent  = Order.create!(user: user, business_round: round, client: client, kind: "remission",
                           status: "transmitted", local_folio: "RN-000083", erp_folio: "2B0011",
                           erp_folios: %w[2B0011 2B0012])
    @sent.order_items.create!(position: 1, quantity: 2, unit_price: 50, tax_rate: 16, discount_percent: 0,
                              code: "000003", description: "MARTILLO", unit: "PZA")
    # No viaja: nunca llegó al ERP.
    Order.create!(user: user, business_round: round, client: client, kind: "remission",
                  status: "captured", local_folio: "RN-000084")
    @out = Rails.root.join("tmp", "evidence-test-#{Process.pid}.json").to_s
  end

  teardown { FileUtils.rm_f(@out) }

  def run_export
    Rake::Task["evidence:export"].reenable
    capture_io { with_env("OUT" => @out) { Rake::Task["evidence:export"].invoke } }
  end

  test "exporta solo los transmitidos, con el mismo paquete que la transmisión y sus folios" do
    run_export
    records = JSON.parse(File.read(@out))

    assert_equal 1, records.size
    assert_equal %w[2B0011 2B0012], records.first["claves"]
    # El paquete ES el de la transmisión: no una versión aparte que pueda
    # divergir en forma de la evidencia recibida.
    expected = JSON.parse(Sync::Up.new("http://x").build_payload(@sent.reload).to_json)
    assert_equal expected, records.first["payload"]
    assert_equal "philips2", records.first["payload"]["capturista_usuario"]
  end

  # Un respaldo de antes de `erp_folios` solo trae el singular.
  test "sin la lista de folios usa el folio singular" do
    @sent.update_columns(erp_folios: [])

    run_export

    assert_equal [ "2B0011" ], JSON.parse(File.read(@out)).first["claves"]
  end

  test "sin pedidos transmitidos se niega en vez de escribir un archivo vacío" do
    Order.transmitted.update_all(status: "captured")

    assert_raises(SystemExit) { run_export }
    assert_not File.exist?(@out)
  end
end
