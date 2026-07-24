class ActiveSuppliersController < ApplicationController
  # Cambia el proveedor activo de la sesión (solo si el capturista realmente
  # lo representa en la rueda activa).
  def update
    id = params[:supplier_id].to_i
    session[:supplier_id] = id if available_suppliers.any? { |s| s.id == id }

    redirect_back fallback_location: root_path
  end
end
