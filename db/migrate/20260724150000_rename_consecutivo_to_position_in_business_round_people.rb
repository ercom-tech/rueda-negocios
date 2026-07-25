class RenameConsecutivoToPositionInBusinessRoundPeople < ActiveRecord::Migration[8.1]
  def change
    rename_column :business_round_people, :consecutivo, :position
    rename_index  :business_round_people, "idx_brp_round_user_consec", "idx_brp_round_user_position"
  end
end
