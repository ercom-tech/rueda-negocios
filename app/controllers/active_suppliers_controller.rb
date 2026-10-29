class ActiveSuppliersController < ApplicationController
  # Cambia el proveedor activo de la sesión (solo si el capturista realmente
  # lo representa en la rueda activa).
  def update
    # Saneado: un `?supplier_id[]=1` llegaba como arreglo y `to_i` levantaba
    # NoMethodError — la pantalla de error (16ª auditoría).
    id = ParamSanitizing.id(params[:supplier_id])
    session[:supplier_id] = id if available_suppliers.any? { |s| s.id == id }

    redirect_back fallback_location: root_path
  end
end
