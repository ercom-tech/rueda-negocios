require "test_helper"
require "webmock/minitest"

# El job es el dueño de la transacción que hace atómico el reemplazo del
# sync-down (`Sync::Down#run!` NO abre la suya): si un refactor mueve o quita
# ese `ActiveRecord::Base.transaction` de una línea, un export corrupto a
# media importación dejaría el catálogo a medias y los pedidos purgados — y la
# suite seguía verde porque ninguna prueba lo cubría. (5ª auditoría.)
class SyncDownJobTest < ActiveJob::TestCase
  API = "http://api.test".freeze

  test "un export corrupto a media importación revierte el reemplazo completo" do
    user   = User.create!(erp_person_id: 940, username: "cap940", password: "x", role: "capturista")
    round  = BusinessRound.create!(erp_round_id: 3, name: "R", active: true)
    client = Client.create!(erp_client_key: "C1", name: "Cliente previo")
    Order.create!(user: user, business_round: round, client: client, kind: "remission",
                  status: "transmitted", erp_folio: "1A0001", local_folio: "RN-000940")
    Setting.instance.update!(selected_round_erp_id: 3, selected_round_name: "R")
    run = SyncRun.create!(kind: "down", started_at: Time.current, pid: Process.pid)
    stub_request(:get, "#{API}/ruedas/3/export")
      .to_return(status: 200, body: corrupt_export.to_json)

    # La corrupción (cliente sin clave, columna NOT NULL) revienta DESPUÉS del
    # purge y de varios reemplazos: justo el punto medio que la transacción
    # debe cubrir. Ojo: duplicados no sirven de corrupción — `insert_all` trae
    # ON CONFLICT DO NOTHING y los descarta en silencio.
    assert_raises(ActiveRecord::NotNullViolation) do
      with_env("RUEDA_API_URL" => API) { SyncDownJob.perform_now(run.id) }
    end

    assert run.reload.failed?, "la corrida queda cerrada, no running"
    assert Order.exists?(erp_folio: "1A0001"), "el rollback restaura el pedido purgado"
    assert Client.exists?(client.id), "el catálogo anterior sigue intacto"
  end

  private

  # Export mínimo válido hasta clientes, donde la clave ausente viola el
  # NOT NULL local.
  def corrupt_export
    {
      "round" => { "erp_round_id" => 3, "name" => "R", "year" => 2026,
                   "starts_on" => "2026-08-27", "ends_on" => "2026-08-28", "location" => nil },
      "cfdi_uses" => [], "divide_amounts" => [], "users" => [], "salespeople" => [],
      "suppliers" => [], "brands" => [],
      "clients" => [
        { "erp_client_key" => nil, "name" => "SIN CLAVE", "commercial_name" => nil,
          "email" => nil, "erp_salesperson_id" => nil,
          "tax_profiles" => [], "receipt_profiles" => [], "branches" => [] }
      ],
      "products" => [], "people" => []
    }
  end
end
