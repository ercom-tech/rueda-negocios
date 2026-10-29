class ActiveBrandsController < ApplicationController
  # Cambia la marca activa de la sesión (solo si el capturista realmente la
  # representa en la rueda activa) — espejo de ActiveSuppliersController.
  def update
    # Saneado: un `?brand_id[]=1` llegaba como arreglo y `to_i` levantaba
    # NoMethodError — la pantalla de error (16ª auditoría).
    id = ParamSanitizing.id(params[:brand_id])
    session[:brand_id] = id if available_brands.any? { |b| b.id == id }

    redirect_back fallback_location: root_path
  end
end
