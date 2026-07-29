class AllowBrandOnlyMembershipInBusinessRoundPeople < ActiveRecord::Migration[8.1]
  # El ERP modela la asignación "solo marca" con id_proveedor = 0 (espejo del
  # id_marca = 0 de "solo proveedor"): la membresía local debe aceptar
  # proveedor nulo cuando trae marca.
  def change
    change_column_null :business_round_people, :supplier_id, true
  end
end
