class ActiveBrandsController < ApplicationController
  # Cambia la marca activa de la sesión (solo si el capturista realmente la
  # representa en la rueda activa) — espejo de ActiveSuppliersController.
  def update
    id = params[:brand_id].to_i
    session[:brand_id] = id if available_brands.any? { |b| b.id == id }

    redirect_back fallback_location: root_path
  end
end
