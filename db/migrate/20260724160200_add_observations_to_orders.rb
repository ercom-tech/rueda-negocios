class AddObservationsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :observations, :text
  end
end
