class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "running"
      t.jsonb :summary, null: false, default: {}
      t.text :message
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :sync_runs, %i[kind created_at]
  end
end
