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
    get   "menu",       action: :menu,         as: :menu          # estado del menú (lo pide el panel)
  end

  # Cambiar precios desde un archivo (panel del servidor): subir → revisar →
  # aplicar. La revisión vive bajo una ficha (`token`) mientras se decide.
  scope "server/prices", as: :server, controller: :prices do
    get    "/",              action: :index,       as: :prices
    post   "review",         action: :review,      as: :prices_review
    get    "review/:token",  action: :show_review, as: :price_review
    post   "review/:token/apply", action: :apply,  as: :price_review_apply
    delete "/",              action: :destroy,     as: :prices_destroy
  end

  # Reportes de venta (hub de reportes).
  get "reports", to: "reports#index", as: :reports
  get "reports/captured-orders", to: "reports#captured_orders", as: :captured_orders_report
  # La misma pantalla del reporte de pedidos, sobre las cotizaciones.
  get "reports/estimates", to: "reports#estimates", as: :estimates_report
  get "reports/product-options", to: "reports#product_options", as: :product_options_report # autocompletado del filtro de producto
  # Reporte de productos (piezas vendidas). Responde HTML, CSV y Excel: las
  # descargas son la MISMA acción con otro formato, así el archivo sale con
  # exactamente los filtros que se están viendo en pantalla.
  get "reports/products", to: "reports#products", as: :products_report

  # "Generar cotización": el mismo paso 1 del pedido, pidiendo una cotización.
  # Ruta propia para que el menú y el paso 3 tengan a dónde volver sin armar
  # el parámetro a mano.
  get "estimates/new", to: "orders#new", defaults: { document: "estimate" }, as: :new_estimate

  # Levantamiento de pedido.
  resources :orders, only: %i[new create show edit update destroy] do
    collection { get :client_options }         # autocompletado del buscador de cliente
    member do
      get   :product_options                   # autocompletado del buscador de producto
      patch :observations                      # guarda observaciones
      post  :capture                           # finaliza (folio) → resumen
      get   :summary                           # paso 3: resumen con opciones
      get   :pdf                               # descarga PDF del pedido
    end
    resources :order_items, only: %i[create update destroy] do # partidas (Turbo)
      member { get :quote }                    # contenido del modal del Cotizador
    end
    # Aplicar (create) y quitar (destroy) una promoción de la rueda. El id es
    # el de la promoción, no el de un registro intermedio: una promoción está
    # aplicada o no lo está, no hay nada más que guardar.
    resources :promotions, only: %i[show create destroy]
  end

  # Menú principal (destino post-login).
  root "home#index"
end
