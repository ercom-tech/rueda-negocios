Rails.application.routes.draw do
  # Salud (load balancers / uptime).
  get "up" => "rails/health#show", as: :rails_health_check

  # Autenticación de capturistas.
  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # Proveedor/marca activos en la sesión (cuando el capturista representa varios).
  patch "active-supplier", to: "active_suppliers#update", as: :active_supplier
  patch "active-brand",    to: "active_brands#update",    as: :active_brand

  # Panel del servidor (operación del sync). Solo rol server.
  scope "server", as: :server, controller: :server do
    get   "rounds",     action: :rounds,       as: :rounds        # elegir rueda
    patch "rounds",     action: :select_round, as: :select_round  # guardar elección
    post  "sync-down",  action: :sync_down,    as: :sync_down     # obtener información
    post  "sync-up",    action: :sync_up,      as: :sync_up       # transmitir pedidos
    post  "close-round", action: :close_round, as: :close_round   # cerrar rueda (purga pedidos)
  end

  # Reportes de venta (hub de reportes).
  get "reports", to: "reports#index", as: :reports
  get "reports/captured-orders", to: "reports#captured_orders", as: :captured_orders_report
  get "reports/product-options", to: "reports#product_options", as: :product_options_report # autocompletado del filtro de producto

  # Levantamiento de pedido.
  resources :orders, only: %i[new create show edit update destroy] do
    collection { get :client_options }         # autocompletado del buscador de cliente
    member do
      get   :product_options                   # autocompletado del buscador de producto
      patch :observations                      # guarda observaciones
      post  :capture                           # finaliza (folio) → resumen
      get   :summary                           # paso 3: resumen con opciones
      get   :pdf                               # descarga PDF del pedido
      post  :send_email                        # (diferido) envío por correo
    end
    resources :order_items, only: %i[create update destroy] # partidas (Turbo)
  end

  # Menú principal (destino post-login).
  root "home#index"
end
