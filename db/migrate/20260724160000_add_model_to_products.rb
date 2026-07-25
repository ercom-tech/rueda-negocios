class AddModelToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :model, :string # "modelo" del ERP (para la búsqueda)
  end
end
