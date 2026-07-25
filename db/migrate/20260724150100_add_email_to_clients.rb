class AddEmailToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :email, :string
  end
end
