class AddConcurrencyGuardsToSyncRunsAndSettings < ActiveRecord::Migration[8.1]
  # Guardas a nivel BD para dos check-then-act del panel del servidor:
  # - sync_runs: máximo UN run `running` por tipo (dos POST rápidos ya no
  #   pueden encolar jobs duplicados).
  # - settings: fila única real (el singleton `first || create!` podía duplicar
  #   bajo concurrencia). Índice único sobre la expresión constante (true).
  def change
    add_index :sync_runs, :kind, unique: true, where: "status = 'running'",
                                 name: "index_sync_runs_one_running_per_kind"
    add_index :settings, "(true)", unique: true, name: "index_settings_singleton"
  end
end
