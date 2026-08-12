class AddPidToSyncRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_runs, :pid, :integer
  end
end
