require "test_helper"
require "rake"

# Las tareas de consola registran su corrida igual que los jobs del panel.
#
# Sin esto, un sync desde la terminal era INVISIBLE para el panel:
# `SyncRun.running.exists?` daba falso, así que "Cerrar rueda" quedaba
# habilitado y su borrado podía correr encima del `find_each` del rake — el
# pedido entra al ERP y el `update!` del folio escribe sobre una fila ya
# borrada, sin excepción, y el folio se pierde. El README presenta el rake al
# mismo nivel que el panel, así que es un camino de operación real.
class SyncRakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task.clear
    Rake.application = Rake::Application.new
    # La lista vacía al final es necesaria: por omisión `rake_require` usa `$"`
    # y a partir del segundo test daría el archivo por cargado sin definir nada.
    Rake.application.rake_require("tasks/sync", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
    SyncRun.delete_all
  end

  teardown { SyncRun.delete_all }

  def run_task(name)
    Rake::Task["sync:#{name}"].reenable
    Rake::Task["sync:#{name}"].invoke
  end

  test "sync:down aborta si ya hay una corrida en curso" do
    SyncRun.create!(kind: "up", started_at: Time.current)

    error = assert_raises(SystemExit) do
      with_env("RUEDA_API_URL" => "http://api.test", "RUEDA_ID" => "3") { run_task("down") }
    end

    assert_equal 1, error.status
    assert_equal 1, SyncRun.count, "no debe crear una corrida encima de la viva"
  end

  test "sync:up aborta si ya hay una corrida en curso" do
    SyncRun.create!(kind: "down", started_at: Time.current)

    assert_raises(SystemExit) do
      with_env("RUEDA_API_URL" => "http://api.test") { run_task("up") }
    end

    assert_equal 1, SyncRun.count
  end

  # Lo que hace visible el rake para el panel: mientras corre existe un SyncRun
  # `running`, que es justo lo que consultan las guardas de las tres
  # operaciones. Se comprueba con el sync-up, que aquí no tiene nada que
  # transmitir y por tanto termina limpio.
  test "sync:up deja registrada la corrida y la cierra" do
    with_env("RUEDA_API_URL" => "http://api.test") { run_task("up") }

    run = SyncRun.latest("up")
    assert_not_nil run, "la corrida de consola debe quedar registrada"
    assert run.completed?
    assert_not_nil run.finished_at
    assert_equal 0, SyncRun.running.count, "no debe quedar ninguna viva"
  end

  # Ctrl-C o kill no son StandardError: no pasan por los rescue de la tarea.
  # Sin el `ensure`, la corrida quedaba `running` para siempre — captura
  # pausada, panel girando y "Cerrar rueda" bloqueado hasta reiniciar el
  # servidor. (5ª auditoría.)
  test "una interrupción cierra la corrida en vez de dejarla running" do
    user   = User.create!(erp_person_id: 9402, username: "cap_int", password: "x", role: "capturista")
    round  = BusinessRound.create!(erp_round_id: 9402, name: "Rueda int", active: true)
    client = Client.create!(erp_client_key: "RK02", name: "Cliente int")
    Order.create!(user: user, business_round: round, client: client, kind: "remission",
                  status: "captured", local_folio: "RN-000901")
    stub_request(:post, "http://api.test/pedidos").to_raise(Interrupt)

    assert_raises(Interrupt) do
      with_env("RUEDA_API_URL" => "http://api.test") { run_task("up") }
    end

    run = SyncRun.latest("up")
    assert run.failed?, "la corrida no debe quedar running"
    assert_match(/se quedó a medias/, run.message)
  end

  # Misma regla que el panel: la condición previa se valida ANTES de abrir la
  # corrida. Si se validara después, algo que nunca llegó a intentarse quedaría
  # registrado como corrida fallida y ensuciaría el historial.
  test "una condición previa no deja corrida registrada" do
    user   = User.create!(erp_person_id: 9401, username: "cap_rake", password: "x", role: "capturista")
    round  = BusinessRound.create!(erp_round_id: 9401, name: "Rueda rake", active: true)
    client = Client.create!(erp_client_key: "RK01", name: "Cliente rake")
    Order.create!(user: user, business_round: round, client: client, kind: "remission")

    assert_raises(SystemExit) do
      with_env("RUEDA_API_URL" => "http://api.test") { run_task("up") }
    end

    assert_equal 0, SyncRun.count, "una condición previa no debe dejar corrida"
  end

  private

  def with_env(vars)
    previous = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end
end
