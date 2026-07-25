class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.integer :selected_round_erp_id

      t.timestamps
    end
  end
end
