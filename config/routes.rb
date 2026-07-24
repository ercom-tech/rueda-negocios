Rails.application.routes.draw do
  # Salud (load balancers / uptime).
  get "up" => "rails/health#show", as: :rails_health_check

  # Autenticación de capturistas.
  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # Placeholder autenticado (destino post-login). La navegación real llega en
  # arcos siguientes.
  root "home#index"
end
