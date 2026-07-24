Rails.application.routes.draw do
  # Salud (load balancers / uptime).
  get "up" => "rails/health#show", as: :rails_health_check

  # Autenticación de capturistas.
  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # Proveedor activo en la sesión (cuando el capturista representa a varios).
  patch "active-supplier", to: "active_suppliers#update", as: :active_supplier

  # Placeholder autenticado (destino post-login). La navegación real llega en
  # arcos siguientes.
  root "home#index"
end
