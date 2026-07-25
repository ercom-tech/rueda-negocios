class AddSelectedRoundNameToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :selected_round_name, :string
  end
end
