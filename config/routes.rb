Rails.application.routes.draw do
  # Salud (load balancers / uptime).
  get "up" => "rails/health#show", as: :rails_health_check

  # Autenticación de capturistas.
  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # Proveedor activo en la sesión (cuando el capturista representa a varios).
  patch "active-supplier", to: "active_suppliers#update", as: :active_supplier

  # Reportes de venta (hub de reportes).
  get "reportes", to: "reports#index", as: :reports

  # Levantamiento de pedido.
  resources :orders, only: %i[new create show] do
    collection { get :client_options }         # autocompletado del buscador de cliente
    member do
      get   :product_options                   # autocompletado del buscador de producto
      patch :observations                      # guarda observaciones
    end
    resources :order_items, only: %i[create update destroy] # partidas (Turbo)
  end

  # Menú principal (destino post-login).
  root "home#index"
end
