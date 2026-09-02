# Ordenamiento del reporte de pedidos capturados.
#
# La columna llega por URL, así que **nunca se interpola en el SQL**: se busca
# en `COLUMNS` y lo que no esté ahí cae al orden por omisión. Un `?sort=` es
# entrada del usuario como cualquier otra.
#
# El orden se aplica en SQL, ANTES de paginar. Ordenar la página ya recortada
# daría una tabla que se ve ordenada y miente: la primera página seguiría
# trayendo los mismos 25 pedidos de siempre, solo que acomodados entre sí.
class OrdersSort
  DEFAULT_KEY = "date".freeze
  DEFAULT_DIR = "desc".freeze

  # Cada columna dice cómo se ordena. `joins` son las asociaciones que hay que
  # traer para que el SQL resuelva; `aggregate` marca las que se calculan de
  # las partidas y necesitan el LEFT JOIN agregado.
  #
  # `Arel.sql` es seguro aquí porque estas cadenas son literales del código,
  # no vienen de la petición — lo que viene de fuera es solo la LLAVE.
  COLUMNS = {
    # Capturista: lo que muestra la celda es el nombre completo con caída al
    # username, así que se ordena por eso mismo y no por `name` a secas (que
    # dejaría a los usuarios sin nombre todos juntos al principio).
    "user" => { sql: "TRIM(CONCAT_WS(' ', users.name, users.paternal_surname, users.maternal_surname))",
                fallback: "users.username", joins: :user },
    # Fecha y hora salen de la MISMA columna: las dos ordenan por ella. Ordenar
    # "hora" por la hora del día mezclaría los días del evento.
    "date" => { sql: "orders.created_at" },
    "time" => { sql: "orders.created_at" },
    "client" => { sql: "clients.commercial_name", fallback: "clients.name", joins: :client },
    "salesperson" => { sql: "salespeople.name", joins: { client: :salesperson } },
    # Espeja EXACTAMENTE lo que la celda muestra (`Order#folio`), incluido el
    # "(borrador)" de un pedido sin folio todavía. Ordenar por la columna cruda
    # dejaba a los borradores en NULL y, con NULLS LAST, clavados al final en
    # las DOS direcciones: por más que se invirtiera el orden no se movían, y
    # la columna parecía no funcionar. Con el texto visible se ordenan como lo
    # que se ve, y el paréntesis los agrupa antes de las claves RN- (2026-09-02).
    "folio" => { sql: "COALESCE(NULLIF(orders.local_folio, ''), NULLIF(orders.erp_folio, ''), '(borrador)')" },
    "items" => { sql: "matching.items_count", aggregate: true },
    "total" => { sql: "matching.items_total", aggregate: true },
    # Por el FLUJO, no alfabético: alfabético da capturado/borrador/transmitido,
    # que no significa nada para quien lee el reporte.
    "status" => { sql: "CASE orders.status WHEN 'draft' THEN 0 WHEN 'captured' THEN 1 ELSE 2 END" }
  }.freeze

  attr_reader :key, :dir

  def initialize(params)
    @key = COLUMNS.key?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_KEY
    @dir = params[:dir].to_s == "asc" ? "asc" : DEFAULT_DIR
  end

  # ¿Está esta columna ordenando ahora, y en qué sentido? Lo usa el encabezado
  # para pintar la flecha y para decidir a dónde apunta su enlace.
  def active?(column) = key == column

  def direction_for(column) = active?(column) ? dir : nil

  # El clic siguiente sobre la MISMA columna invierte; sobre otra, empieza
  # ascendente. Una columna que empezara descendente sorprende.
  def next_dir_for(column) = active?(column) && dir == "asc" ? "desc" : "asc"

  def to_params
    return {} if key == DEFAULT_KEY && dir == DEFAULT_DIR

    { sort: key, dir: dir }
  end

  # Aplica el orden al scope. `products` (ids) llega cuando hay filtro de
  # partida activo: entonces "Renglones" y "Total" son los de las partidas que
  # COINCIDEN —que es lo que la pantalla muestra—, no los del pedido completo.
  # Ordenar por el total del pedido mientras se ve otro número sería
  # incomprensible.
  def apply(scope, products = nil)
    column = COLUMNS.fetch(key)
    # LEFT y no INNER: `joins` esconde las filas sin la asociación, así que
    # ordenar por vendedor hacía DESAPARECER los pedidos de clientes sin
    # vendedor asignado — un filtro disfrazado de orden, y silencioso.
    scope  = scope.left_joins(column[:joins]) if column[:joins]
    scope  = scope.joins(aggregate_join(products)) if column[:aggregate]

    # Desempate por id: sin él, dos pedidos con el mismo valor pueden salir en
    # orden distinto entre páginas y un mismo pedido aparecer dos veces o
    # ninguna. Con `created_at` no basta: dos altas del mismo segundo empatan.
    order = [ "#{column[:sql]} #{sql_dir}" ]
    order << "#{column[:fallback]} #{sql_dir}" if column[:fallback]
    order << "orders.id #{sql_dir}"
    scope.reorder(Arel.sql(order.join(", ")))
  end

  private

  # NULLS LAST en las dos direcciones: un pedido sin vendedor o sin folio no
  # debe encabezar la tabla solo por estar vacío.
  def sql_dir = "#{dir.upcase} NULLS LAST"

  # LEFT JOIN a un agregado y no subquery correlacionada, que es la norma del
  # proyecto para agregados. LEFT y no INNER: un pedido sin partidas —un
  # borrador recién creado— tiene que seguir apareciendo.
  def aggregate_join(products)
    total_sql = if products
      ActiveRecord::Base.sanitize_sql_array([ Order::MATCHING_ITEMS_TOTAL_SQL, products ])
    else
      Order::ITEMS_TOTAL_SQL
    end
    count_sql = if products
      ActiveRecord::Base.sanitize_sql_array([ "COUNT(*) FILTER (WHERE order_items.product_id IN (?))", products ])
    else
      "COUNT(*)"
    end

    Arel.sql(<<~SQL.squish)
      LEFT JOIN (
        SELECT order_items.order_id,
               #{count_sql} AS items_count,
               #{total_sql} AS items_total
        FROM order_items GROUP BY order_items.order_id
      ) matching ON matching.order_id = orders.id
    SQL
  end
end
