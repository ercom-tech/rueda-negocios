# Auditorías de código — julio 2026

Historial de las dos auditorías del proyecto y su remediación. **Ambas
cerradas al 100%**; se conserva como referencia de qué se revisó y con qué
criterio, no como pendientes.

Extraído de `memory.md` el 2026-08-10 (ahí solo diluía las reglas vigentes).

## Auditoría 2026-07-25 — remediación (por severidad, de + a -)

Auditoría en 5 ejes (usabilidad, doc↔código, convenciones, calidad/patrones,
seguridad). Reporte: artifact "Auditoría — rueda-negocios & rueda-api".
Estado de los hallazgos ALTA:

- [x] **A1** `rake sync:up` usaba `Order.submitted` (scope inexistente) →
  `Order.captured` en `lib/tasks/sync.rake:40`.
- [x] **A2** contraseña del server sin default en producción: `db/seeds.rb`
  exige `SEED_SERVER_PASSWORD` en prod; default `rueda2026` solo dev/test.
- [x] **A3** N+1: `Sync::Up#pending` precarga `order_items: :product`;
  `ReportsController#captured_orders` precarga `:order_items`.
- [~] **A4** cobertura de tests:
  - [x] **A4a** rueda-negocios (Minitest + webmock): `order_test` (totales/estado),
    `sync/down_test` (guarda, replace, preserva server, cleanup), `sync/up_test`
    (transmite, idempotencia, payload, fallo). 12 tests, suite en verde (17 total).
  - [x] **A4b** rueda-api: harness Minitest con `Sequel.mock` (sin conectar al
    ERP) + `order_create_test` (folio prefijo+consecutivo, idempotencia, prefijo
    faltante, capturista ausente, N partidas). 6 tests en verde.
    Trampas resueltas: `DB.sqls` de Sequel.mock **se drena al leerse** (capturar
    una vez); mock fresco por test (`remove_const`/`const_set`) para no arrastrar
    estado de transacción tras un rollback.

**ALTA: todos resueltos (A1–A6).**

MEDIA (por bloques temáticos; ver artifact de auditoría):
- [x] **Bloque 3 (quick wins):** M2 (anclar `config.hosts`), M8 (ruta/acción
  `submit`→`capture`), M10 (`Order::STATUS_COLORS` centralizado), M17 (rubocop en
  rueda-api, corre limpio), M18 (docs: idempotencia resuelta, `Order.captured`).
- [x] **Bloque 5 (correctitud ERP):** M1 (no autoseleccionar el fiscal cuando
  el cliente tiene varios — el ERP no marca principal; `apply_header_defaults`);
  M3 (rueda-api `OrderCreate#validate!`: existencia de cliente/vendedor/productos
  + coherencia de montos, SIN recomputar precios de rueda); M4 (idempotencia por
  la PK única de `vta_pedido` con `rescue Sequel::UniqueConstraintViolation`);
  M5 (`next_folio` deriva el corte de `length(prefijo)`). Tests rueda-api: 11 en
  verde.
- [x] **Bloque 6 (robustez sync):** M6 — timeouts HTTP configurables
  (`RUEDA_API_OPEN_TIMEOUT`/`READ_TIMEOUT`) en `ApiClient`/`Sync::Up`; un error
  de red por pedido marca fallido y continúa (no aborta la transmisión).
- [x] **Bloque 4 (tokens de color):** M9 — paleta de marca en `@theme`
  (`app/assets/tailwind/application.css`): `brand-gold`/`brand-gold-dark`/
  `brand-coral`/`brand-coral-dark`/`brand-cream`. ~64 usos de hex migrados en 16
  vistas; unificados los 3 pares divergentes (#f1d24e→gold, #f4efe0→cream,
  #b9553f→coral-dark). Fuente única de verdad.
- [x] **Bloque 7a (UX):** M7 (correo/WhatsApp en `summary` atenuados con badge
  "Próximamente", sin modal ni acción — se enviarán al sincronizar); M14 (`flash`
  con `id` estable + locals `notice/alert`; al fallar `OrderItems#update` repinta
  con el valor válido anterior y avisa por Turbo Stream, no revierte en silencio);
  M15 (acción `Orders#destroy` "Descartar pedido" con modal de confirmación en
  `show`, solo si `editable?`). Validado en navegador.
- [x] **Bloque 7b-i (a11y modal/flash):** M11 (`_confirm_dialog` con
  `role="dialog"`/`aria-modal`/`aria-labelledby`/`aria-describedby` e ids únicos;
  `modal_controller` mueve el foco al primer control, atrapa Tab dentro
  —focus-trap enganchado internamente, sin tocar las 5 vistas— y al cerrar
  restaura el foco previo); M16 (`flash_controller` nuevo: auto-dismiss 5s/8s +
  botón ✕; el mensaje lleva `pointer-events-auto`). Validado en navegador
  (Tab cicla, Esc cierra y restaura foco, ✕ cierra).
- [x] **Bloque 7b-ii (a11y select/autocomplete):** M12 (`custom_select` navega
  con teclado también cuando NO es filtrable —el botón recibe `keydown->navigate`
  y ↑/↓ abre el panel—; ARIA completo: botón `aria-haspopup/aria-expanded`, `ul`
  `role="listbox"`, opciones `role="option"`/`aria-selected`, `aria-activedescendant`
  en el elemento con foco); M13 (`autocomplete` muestra "Buscando…" (role=status)
  y, ante fallo de red, aviso `role=alert` en vez de reventar en silencio; input
  `role="combobox"` con `aria-expanded`/`aria-activedescendant`; resultados
  `role="listbox"`/`option`). Validado en navegador (teclado en select no
  filtrable, activedescendant, y error de red simulado interceptando fetch).
  **Con esto MEDIA queda cerrado; siguen los BAJA.**

BAJA (por grupos temáticos; 14 hallazgos + login-throttling movido a strengthening):
- [x] **Grupo A (correctitud/robustez):**
  - Bug pérdida de datos: `Sync::Down#import_users` borraba a TODOS los
    capturistas si el export venía sin usuarios (`where.not(col: [])` → `AND 1=1`).
    Fix: cleanup solo si `erp_keys.any?` + `.compact`. Test nuevo. (rueda-negocios)
    **(Superado 2026-07-26: el usuario definió lo contrario — REPLACE pleno; ver
    la nota de sync-down al final de la sección de la 2ª auditoría.)**
  - Tope de descuento server-side: `OrderItem#discount_within_limits` valida
    contra `product.max_discount` (%; 0 = sin descuento, nil = hasta 100).
    Mensajes en `:base` (evita cambiar default_locale). `OrderItems#update`
    muestra el error real en el flash. Tests de modelo. (rueda-negocios)
  - rueda-api: `POST /pedidos` con JSON inválido → 400 (antes 500); `/health`
    no filtra `e.message` al cliente. Tests rack-test (test/application_test.rb,
    carga `app/application.rb` con LOGGER stub, sin config/application.rb).
  Todo validado (suite + navegador para el flash de descuento).
- [x] **Grupo C (UX/inclusividad):**
  - Touch targets ≥44px en `_item_row`: botón 🗑 (`h-11 w-11`) y campos
    cantidad/descuento (`h-11`). Medido en navegador (44×44 / 64×44).
  - Confirmaciones: el `turbo-confirm` nativo ya no existía (migró al modal en
    M15). Criterio unificado: el modal se reserva para lo destructivo/pesado;
    cerrar sesión es reversible → `button_to` directo en los 3 lugares (se quitó
    el modal de logout del rol server en `home/index`).
  - Saludo neutro: "Bienvenido, …" → "Hola, …" (`sessions_controller`).
- [x] **Grupo D (convenciones/limpieza/docs):**
  - Borrado `hello_controller.js` (scaffolding sin usar; sin referencias).
  - Docs Postgres: README rueda-negocios "16/17" → "16" (consenso con CLAUDE.md
    y docs; el ERP corre 16, aunque el dev local del usuario es 17.10 Postgres.app).
  - README rueda-api: sección "## Tests" con `bundle exec rake test`.
  - `orders_controller`: variable local `nuevo` → `new_client`. NO se tocaron
    `prefijo`/`id_rueda` en rueda-api: son columnas reales del ERP
    (`cnf_persona.prefijo`, `r.id_rueda`); renombrarlas rompería la
    correspondencia variable↔columna en el SQL (el hallazgo los clasificó mal).
- [x] **Grupo B (rueda-api export):** `deep_coerce` (recorría ~13k productos en
  memoria para BigDecimal→string) eliminado; los 5 NUMERIC de `products` se
  castean con `trim_scale(...)::text` en SQL (precios idénticos, enteros sin
  `.0`, cero notación científica). `#{EMPRESA}` interpolado → placeholder `?`.
  Validado byte a byte contra la BD dev (rueda 3): JSON semánticamente idéntico,
  ~80 KB más chico. **AUDITORÍA CERRADA.**
- [x] **Rutas ES/EN unificadas a inglés:** en `routes.rb`, `servidor`→`server`,
  `ruedas`→`rounds`, `reportes`→`reports`, `pedidos-capturados`→`captured-orders`.
  Solo cambió `routes.rb`: los `as:`/helpers ya eran inglés y las vistas usan
  helpers (nada hardcodeado). Validado en navegador (`/reports`,
  `/reports/captured-orders`). El texto español de la UI y el username `servidor`
  del rol server NO son rutas y se conservan.
- No abordados por decisión: login throttling (→ strengthening con D1–D4
  diferidos), y `prefijo`/`id_rueda` en rueda-api (espejan columnas del ERP).
- [x] **A5** errores del encabezado: panel "Faltan datos obligatorios: …" +
  ring rojo en los `custom_select` inválidos (`invalid:` en el partial).
- [x] **A6** tarjetas no implementadas (menú + reportes) marcadas "Próximamente"
  (atenuadas, no clickeables) vía `soon:` en `_menu_card`/`_report_card`.
  - **Ajuste posterior (a pedido del usuario):** en el home (`_menu_card`) el
    badge "Próximamente" pasó de arriba-derecha a **abajo-derecha**; en ambos
    hubs el badge es **amarillo sólido** (`bg-brand-gold` + ring/sombra) en vez
    de gris translúcido. Clave de diseño: para que el badge resalte a plena
    opacidad, el estado "soon" atenúa el **contenido** con `opacity-60` y el
    **fondo** con alpha (`bg-brand-*/60`) — el alpha en el color NO afecta a los
    hijos, `opacity` sí. Validado en navegador (capturista + reportes).

Media/baja/diferidos: ver el artifact de auditoría.

## Auditoría 2026-07-26 (2ª pasada, post-remediación) — remediación

Reporte: artifact "Auditoría — rueda-negocios & rueda-api" (segunda-auditoria).
2 ALTA · 9 MEDIA · 24 BAJA · 0 vulnerabilidades de seguridad nuevas.

- [x] **Bloque 1 (ALTA):**
  - **A1 camino de regreso al pedido:** filas del reporte enlazan a `order_path`;
    "Volver al pedido" en el resumen. Lectura (`show`/`summary`/`pdf`) usa
    `accessible_orders` (server → todos, capturista → suyos); la escritura sigue
    solo del dueño. Vistas usan `can_edit_order?(order)` (helper en
    ApplicationController: `editable? && dueño`) en vez de `order.editable?` —
    el server abre cualquier pedido en solo lectura. Validado en navegador con
    ambos roles.
  - **A2 colisión de idempotencia:** FECEGO NO tolera microsegundos en
    `hora_pedido` (confirmado por el usuario) → la solución es detección:
    `find_existing` ahora trae folio + total + # partidas; si hay match por
    (cliente, fecha, hora) pero el contenido difiere (total > $0.01 o # partidas)
    → `Error` 422 "colisión de idempotencia" en vez de responder idempotente.
    El sync-up lo marca fallido y visible (remedio: recapturar el pedido). El
    reintento legítimo (mismo contenido) sigue idempotente. Tests: 16 en verde.
- [x] **Bloque 2 (robustez sync, M1-M3):** M1 — `JSON::ParserError` y
  `ApiClient::Error` en el rescue por pedido de `Sync::Up#run!` (un 200 no-JSON
  marca fallido ese pedido y el lote sigue); M2 — guard `folio.to_s.strip.empty?`
  → un 2xx sin `clave_pedido` es fallido reintentable, nunca transmitido-sin-folio
  (pending solo re-selecciona captured, quedaría atascado); M3 — `ApiClient#get`
  envuelve `JSON::ParserError` en `ApiClient::Error` (el panel muestra flash,
  no 500). Tests: 4 nuevos (aislamiento de lote incluido); suite 28/106.
- [x] **Bloque 3 (M4, índices trigram):** migración `pg_trgm` + 8 índices GIN
  `gin_trgm_ops` (products: description/model/part_number/`CAST(erp_product_id
  AS TEXT)` como índice de expresión —el opclass va INLINE en el string, la
  opción `opclass:` solo aplica a columnas—; product_suppliers.supplier_sku;
  clients: name/commercial_name/erp_client_key). `Product.search` reestructurado:
  el SKU salió del OR-con-LEFT-JOIN (que impedía índices por tabla) a una rama
  `UNION` dentro de `id IN (…)` — cada rama entra por su índice (BitmapOr).
  De paso `sanitize_sql_like` (cierra B17). Medido: 34.5 ms (seq scan 13,196
  filas) → **0.17 ms** (~200×), conteos idénticos (39/20). Clientes (47 filas):
  el planner elige seq scan correctamente; el índice queda para cuando crezca.
- [x] **Bloque 4 (UX, M5-M7):** M5 — tabla de partidas responsiva: Consecutivo/
  No. de parte/Unidad ocultas bajo `lg` (`hidden lg:table-cell`); a 800px quedan
  acciones+Código+Descripción+Cantidad+Precio+Descuento+Total SIN scroll
  horizontal (medido). M6 — feedback de auto-guardado: `form_submit_controller`
  con target `status` + `flashStatus` en `turbo:submit-end` (solo con éxito);
  "Guardado ✓" 2s junto al textarea de observaciones (+ aria-label, adelanta
  parte de B14). M7 — `public/406-unsupported-browser.html` reescrita en
  español con la identidad de la app (allow_browser la sirve por default).
  Todo validado en navegador (resize a 800px incluido).
- [x] **Bloque 5 (contrato+docs, M8-M9):** M8 — el 500 genérico de rueda-api
  ahora incluye `message: "Error interno."` (contrato `{error, message}`
  uniforme con 400/422; el detalle sigue solo en el log). Test con
  `app.set :raise_errors, false` (en test Sinatra propaga excepciones y el
  handler `error do` no corre sin apagarlo). M9 — memory.md: corregida la
  referencia fantasma a `rueda-api/docs/contract.md` (el contrato vive en
  `docs/erp-esquema-*.md`) y 10 notas "(superado/hoy …)" en las secciones
  añejas (deep_coerce, modal de correo, Cancelar→turbo_confirm,
  draft/submitted, orders#submit, rutas /reportes). Ajuste a M5 pedido por el
  usuario: "Consecutivo" visible en angosto como "#" (antes oculto); No. de
  parte/Unidad siguen ocultas bajo lg. **Con esto MEDIA de la 2ª auditoría
  queda cerrado; siguen los BAJA.**

BAJA 2ª auditoría (por grupos):
- [x] **Grupo A (integridad de pedidos):**
  - B1: `max_discount` nil = **0** (sin descuento) — decisión del usuario. Antes
    nil caía a tope 100%. Partidas sin producto tampoco admiten descuento.
  - B2: partida sin precio (`unit_price` 0) inválida — al agregar un producto
    sin precio el flash avisa y no se agrega (`OrderItems#create` pasó de
    `create!` a manejo con errores). Validado en navegador (producto 426).
  - B3: `min_sale_quantity` **ELIMINADA** (migración). Se investigó cablearla
    como "venta en múltiplos de empaque": la fuente ERP es
    `com_producto_has_empaque` (minimo=true, ~6,520 productos con cantidad
    6/10/4/12/20…), PERO al validar contra 1.8M de partidas reales del ERP solo
    ~78-85% son múltiplos exactos (consistente 2022-2026) → NO es regla dura
    del negocio; el usuario decidió eliminar la columna.
  - B4: rueda-api `validate!` rechaza pedidos sin partidas (422).
  Suites: rueda-negocios 30/110 · rueda-api 18/43.
- [x] **Grupo B (PDF, importe en letra):** B5 — el total se cuantiza a 2
  decimales ANTES de partir entero/centavos (100.999 daba "CIEN PESOS 100/100";
  ahora "CIENTO UN PESOS 00/100"). B6 — `integer_to_words` recursivo en
  millones (>10^9 ya no truena). Bonus destapado por los tests: apócope
  "uno"→"un" antes de sustantivo ("ciento UN pesos", "veintiún mil" — antes
  "CIENTO UNO PESOS"). Tests dedicados (order_generator_test) + smoke render.
- [x] **Grupo C (concurrencia menor):** B7 — índice único parcial
  `sync_runs(kind) WHERE status='running'` (máx. un run corriendo por tipo);
  el controller rescata `RecordNotUnique` → mismo alert amigable. B8 — índice
  singleton en `settings` (expresión `(true)` única) + `Setting.instance` con
  rescue→relee. Tests de ambas guardas. Trampa: Minitest 6 ya NO trae
  `minitest/mock` integrado — el stub del test de carrera se hizo con
  `define_singleton_method` + `remove_method`. Suite 39/124.
- [x] **Grupo D (UX menor):** B9 — paginación con pagy (25/página) en el
  reporte de pedidos + nav propia (solo aparece con >1 página). B10 — el panel
  del server da guía accionable en vez de e.message crudo (detalle al log).
  B11 — "Ver PDF"/"Generar PDF" unificados a "Descargar PDF" (es lo que hacen).
  B12 — login "Enviar"→"Iniciar sesión". B13 — "Guardar"→"Finalizar pedido" en
  el detalle (+ flash "antes de finalizar"). B14 — aria-labels en cantidad/
  descuento con el nombre del producto. B15 — contraste white/50-60 → white/70
  en server/rounds. B16 — placeholder del buscador corto ("Busca por código,
  nombre, modelo o No. de parte"). Validado en navegador.
- [x] **Grupo E (limpieza):** B18 — `EMPRESA = 1` compartida en
  `rueda-api/app/constants.rb` (antes triplicada; test_helper también la carga).
  B19 — locals de order_create a inglés (`vend`→`salesperson_id`,
  `faltantes`→`missing`, `esperado`→`expected`, `existentes`→`found`).
  B20 — `layouts/application` se CONSERVA como fallback de convención (si una
  vista futura olvida `layout "auth"` cae aquí con CSS y csrf, no pelona) +
  `lang="es"` + comentario. B21 — enum simbólico (`status: :captured` /
  `:transmitted`). B22 — comentario `Locals:` uniforme en los 3 partials en
  prosa. Smoke del export contra la BD real (13,196 productos con la constante
  compartida). **2ª AUDITORÍA COMPLETAMENTE REMEDIADA** — pendientes solo los
  registros sin acción: B23 (colisión con escritor ERP nativo, baja confianza)
  y B24 (revalidación de precios → strengthening).

**Sync-down / usuarios — regla definitiva (2026-07-26, decisión del usuario):**
los usuarios se reemplazan IGUAL que las demás tablas (replace pleno). Si el
export viene sin usuarios, se limpian TODOS los capturistas — que la rueda no
tenga usuarios asignados es problema operativo del ERP, no del sitio. Esto
REVIERTE el guard `erp_keys.any?` del Grupo A de los BAJA (1ª auditoría), que
trataba el export vacío como error a protegerse. Única excepción que se
mantiene: el usuario `server` (seedeado) sobrevive siempre — es infraestructura
de la app, no dato del ERP. Test invertido en `down_test`.

**"Cerrar rueda" (2026-07-26):** acción nueva del panel del server para
encadenar ruedas en la misma laptop. `Sync::CloseRound.run!`: purga TODOS los
pedidos locales (transmitidos ya viven en el ERP; borradores son capturas
incompletas), desactiva la rueda y limpia la selección — así el sync-down de
la siguiente rueda pasa su guarda (`Order.exists?`). Guarda propia: NO cierra
si hay capturados sin transmitir (ventas que se perderían). UI: card 5 del
menú server (neutra oscura, destructiva → modal). Ruta `POST /server/close-round`.
Tests del servicio (3) + guarda validada en navegador.
Ajuste 2026-07-28 (pedido del usuario): también **borra el historial de
`SyncRun`** — el panel mostraba la última descarga/transmisión de la rueda ya
cerrada; ese historial pertenece a la rueda, el panel debe arrancar limpio.
Segunda guarda: `SyncInProgressError` si hay un run `running` (borrarle su
SyncRun al job vivo lo rompería). +2 tests.
Ajuste 2026-07-28 (regla del usuario): **no se puede elegir otra rueda con una
en curso** — el cambio de rueda pasa SIEMPRE por "Cerrar rueda" (y sus
guardas). Guard en el controller sobre `rounds` Y `select_round` (URL directo/
back no se la brincan) + card "Elegir rueda" deshabilitada en el menú
(opacity-60, sin link, hint "Ciérrala para elegir otra"). El estado
"Seleccionada" de la pantalla de ruedas quedó muerto y se eliminó (solo se
alcanza sin selección). Equivocarse de rueda no estorba: "Cerrar rueda" con 0
pedidos es gratis. Tests de integración (4) con webmock.
Ajuste 2026-07-28 (regla del usuario, cierre del embudo): **sin rueda no se
opera nada**. (a) Capturistas ni siquiera entran: login bloqueado sin
`active_round` (422 con "No hay rueda en curso en esta laptop…") y guard de
sesión `require_round_for_capturista` en ApplicationController que expulsa
(reset_session → login) a los que tenían sesión viva cuando se cerró la rueda
— SessionsController lo salta para que login/logout funcionen siempre. El rol
server entra siempre (es quien carga la rueda). (b) Panel server sin
selección: SOLO vive "Elegir rueda" — Transmitir/Reportes/Cerrar quedan
deshabilitadas (mismo patrón disabled) + guards por URL directo en `sync_up`
("no hay pedidos que transmitir"), `close_round` ("No hay rueda que cerrar")
y `ReportsController#require_round` (criterio: selección o rueda activa).
Con esto el flujo es un embudo estricto: elegir → obtener → operar → cerrar
→ elegir. Tests de integración (6, no_round_access_test).
Ajuste 2026-07-28 (regla del usuario): **sesión única por usuario, "el
último login gana"** — `has_secure_token :session_token` en User; cada login
regenera el token y lo guarda en la cookie; el guard `require_current_session`
(ApplicationController, entre require_login y el guard de rueda; Sessions lo
salta) cierra con "Tu usuario inició sesión en otro equipo" toda sesión cuyo
token ya no coincida. Se eligió este sabor sobre "bloquear el segundo login"
porque con cookies el servidor no sabe cuándo murió una sesión (navegador
cerrado, tablet sin pila) y bloquearía usuarios para siempre sin TTL/
heartbeat. El logout de una sesión desplazada no toca el token (solo el login
lo regenera), así no tumba a la sesión nueva. Tests (3,
single_session_test, con open_session para simular dos equipos).
Ajuste 2026-07-29 (pedido del usuario): **auditoría de logins** — tabla
`login_events` (un renglón por intento: user FK `on_delete: :nullify` +
username tecleado, success, ip, user_agent, created_at). `success: false`
cubre credenciales malas, usuario inexistente/inactivo Y capturista
bloqueado sin rueda ("no se abrió sesión"). Sobrevive al replace del
sync-down (FK anula, evento queda con el username). Los fallidos son la
materia prima del throttling diferido a strengthening. Sin UI todavía —
consultable por consola; candidato a reporte del panel server. Tests (5,
login_events_test).
Ajuste 2026-07-28: **seleccionar rueda pide confirmación con modal** (mismo
patrón modal + `home/confirm_dialog`, que ahora acepta el local opcional
`params` para el PATCH con erp_round_id/name) — avisa que para cambiarla
después habrá que cerrarla.
Ajuste 2026-07-28 (pregunta del usuario): **una corrida de sync viva bloquea
lanzar CUALQUIER otra** (no solo del mismo tipo): `SyncRun.running.exists?`
en sync_down y sync_up — cierra la ventana de "descarga a media transmisión"
que podía pisar al job en vuelo. El mismo tipo ya estaba doblemente blindado
(guard + índice único parcial: un running por tipo, la carrera exacta la
para Postgres con RecordNotUnique). El menú refleja el bloqueo en vivo:
el broadcast de SyncRun ahora reemplaza el MENÚ COMPLETO (`#server-menu`,
partial home/server_menu con locals recalculados) en vez de solo la línea de
estado, para que Obtener/Transmitir/Cerrar se deshabiliten/rehabiliten sin
recargar. Validado en navegador: guard cruzado (flash con la descarga
corriendo), botones disabled durante la corrida, nodo del menú reemplazado
al terminar (marcador DOM desapareció) y — punto delicado — los `button_to`
del menú re-inyectado por broadcast SÍ pasan CSRF (Turbo manda el token del
meta tag en el header; el render del canal no tiene sesión). Tests de
integración (4, sync_concurrency_test).

**Universo de productos por capturista (2026-07-26, regla del usuario):** un
capturista puede tener varios proveedores/marcas asignados y ese es su universo
DURO de productos (todos sus proveedores ∪ sus marcas; sin membresía → vacío,
problema operativo del ERP). Cadena completa:
- Export: llave `people` (cnf_rueda_negocios_persona → erp_person/supplier/
  brand_id, marca 0→nil) y `supplier_ids` por producto desde
  **com_proveedor_has_producto** — hallazgo clave: la relación real
  producto↔proveedor NO son los SKUs (com_producto_has_sku: MAKITA tendría 0
  productos por SKUs vs 2,207 reales). ProductSupplier ahora guarda la unión
  (supplier_sku nil cuando no hay SKU).
- Sync-down: `import_people` → business_round_people (omite y reporta
  membresías sin usuario/proveedor local, `skipped_people`).
- App: `User#product_universe(round)`; `product_options` busca DENTRO del
  universo (mensaje si no hay membresía); `OrderItems#create` scopea el find
  al universo (404 ante POST forjado). Validado en navegador con makita1:
  universo 2,134, "martillo" → solo MAKITA, STIHL fuera.
- **PDF del pedido — ajustes de formato (2026-07-29, pedido del usuario):**
  (a) nombre de la rueda en negritas arriba de "Capturado:"; (b) "Capturado:"
  incluye al capturista (full_name/username) y "Renglones" pasó a su propia
  línea; (c) Observaciones debajo del importe en letra (bounding_box en
  flujo, izquierda de los totales); (d) **dirección completa** de la sucursal
  — el export ahora arma calle + no. ext (+ INT.), COL., CP, municipio y
  estado resolviendo los consec_* contra cnf_colonia/cnf_municipio/cnf_estado
  (colonia lleva id_empresa en el join; municipio/estado no, como en la
  ubicación de la rueda). El campo llega por la misma llave `address` del
  export → sin cambios en el import. Requiere sync-down para refrescar
  direcciones ya sincronizadas.
  Segunda ronda: Sucursal ARRIBA de Dirección; Renglones al final del bloque
  derecho (bajo Estatus); totales flush al borde derecho de la tabla de
  partidas — ojo Prawn: la tabla toma su ancho natural, no el del
  bounding_box; hay que fijar column_widths que sumen el ancho del box y
  quitar el padding derecho de la columna de montos.
- **Empaque mínimo de venta — REVIVIDO como regla dura (2026-07-30, pedido
  del usuario):** revierte la decisión de la 2ª auditoría ("no cablear").
  Fuente `com_producto_has_empaque` (MIN(cantidad) con minimo=true, CTE en el
  export → `min_sale_quantity`, ~957 productos en la rueda 3; NULL = sin
  regla). La cantidad debe ser múltiplo exacto
  (OrderItem#quantity_in_package_multiples, mensaje "se vende en múltiplos de
  X"); la partida nueva arranca en el empaque y las flechas ↑/↓ avanzan por
  empaque (data-step-size). La regla es MÁS estricta que el propio ERP
  (~78–85% de ventas reales son múltiplos) — a propósito. Validado E2E en
  navegador (alta→20, flecha→40, 25→422 y repinta 20). Detalle del entorno
  de pruebas: element.focus() NO dispara el evento focus si la ventana no
  tiene foco del SO — los guards de remember/submitIfChanged se prueban
  despachando FocusEvent a mano. Requiere sync-down para poblar empaques.
  Refinamiento (cazado por el usuario): el `min` del input debe SER el
  empaque (con min=1, la ↓ desde 10 caía a 1 y desalineaba: 11, 21…) y la
  flecha va al siguiente múltiplo EN SU DIRECCIÓN (15↑→20, 15↓→10), nunca
  bajo el empaque.
- **dividir_facturas en el encabezado (2026-07-29/30, pedido del usuario):**
  `vta_pedido.dividir_facturas` (NUMERIC(18,6), default 0) = importe máximo
  por factura al facturar el pedido (valores reales: 2k/5k/10k/25k…; 0 = no
  dividir). El usuario primero lo llamó "monto_divide" — no existía; el
  nombre real se confirmó consultando el esquema. Cadena completa: columna
  espejo en orders + campo en paso 1 (SOLO visible con tipo Factura, target
  de order-kind) + card del paso 2 ("cada $X" / "No dividir") + payload del
  sync-up + INSERT en rueda-api (`p["dividir_facturas"] || 0`). Validado
  E2E contra el ERP de testing (pedido 1A0017 → 5000; borrado después).
  Trampa repetida: el primer intento insertó 0 porque el rackup de :4568
  servía código de ayer.
  Iteración UI (2026-07-30, pedido del usuario): el campo va DEBAJO de
  Dirección de entrega, a MEDIA columna (como Tipo/Uso CFDI), formato pill
  negra, sin hint, y es un COMBO alimentado por el catálogo del ERP
  `vta_pedido_monto_divide` (7 montos: 0/2k/5k/10k/15k/25k/50k) → export
  `divide_amounts` → tabla local `divide_amounts` (DivideAmount, label
  "No dividir"/"$2,000"). El pedido guarda el MONTO elegido, no FK (igual
  que vta_pedido). Sin catálogo sincronizado el combo no se muestra
  (queda 0). Emparejar selected: valor plano normalizado
  (DivideAmount#option_value / Order#dividir_facturas_option).
- **Código FECEGO a 6 dígitos (2026-07-28, regla del usuario):** el ERP
  guarda `id_producto` como entero pero SIEMPRE lo muestra a 6 dígitos
  (17768 → "017768"). `Product#erp_code` (`format("%06d")`) es la única
  definición del formato; lo usan el autocompletado y el snapshot de partidas
  (`order_items.code`), que arrastra el formato a tabla/resumen/PDF gratis.
  La rama del código busca contra el PADDED — `LPAD(erp_product_id::text,
  6, '0') ILIKE %q%` con índice trigram de EXPRESIÓN (bitmap scan, 0.012ms).
  El primer intento (quitar ceros a la izquierda y buscar contains sobre el
  entero) fue engañoso y el usuario lo cazó: "000081"→"81" traía 003381,
  004817, 008681… Con el padded, un código de 6 completo es exacto por
  construcción (6 dentro de 6 = igualdad), "17768" sigue hallando 017768 y
  "0177" a los 0177xx. Partidas previas al cambio quedarían sin pad
  (snapshot), pero había 0 pedidos. Tests (6).
- **Membresías múltiples y solo-marca (2026-07-28):** el ERP no tenía ningún
  caso real de >1 proveedor / >1 marca (solo 3 makitas con 1 proveedor c/u);
  se insertaron en el ERP de testing 2 renglones para makita1 (90092):
  consecutivo 2 → STIHL (157) y consecutivo 3 → **solo marca** HITOOLS
  (id_proveedor=0, id_marca=22). Eso destapó un hueco: `id_proveedor = 0`
  es la convención ERP de "solo marca" (espejo de id_marca 0), el export NO
  le hacía NULLIF y el import omitía toda membresía sin proveedor → las
  asignaciones solo-marca SE PERDÍAN. Fix: export `NULLIF(id_proveedor, 0)`;
  migración `supplier_id` nullable en business_round_people + `belongs_to
  optional` + validación "proveedor o marca, al menos uno"; import_people
  acepta solo-marca y omite solo referencias rotas o renglones vacíos (+2
  tests). Validado E2E en navegador con makita1: universo = MAKITA ∪ STIHL ∪
  HITOOLS = **8,716** (2,134 + 4,068 + 2,515 exacto contra query directa),
  pill de Proveedor se volvió selector (2 proveedores), búsquedas reales en
  paso 2: "martillo"→MAKITA, "1124-640"→STIHL, "CHECK"→HITOOLS,
  "31820" (BTICINO, fuera) → "Sin resultados". makita2 sigue acotado a
  2,134. Los renglones de prueba QUEDAN en el ERP de testing (borrarlos:
  `DELETE FROM fecego.cnf_rueda_negocios_persona WHERE id_empresa=1 AND
  id_rueda=3 AND id_persona=90092 AND consecutivo IN (2,3);`).

**Guarda del sync-down afinada (2026-07-27, decisión del usuario):** solo
bloquean los pedidos capturados SIN transmitir; borradores y transmitidos se
purgan automáticamente antes del replace (`purged_orders` en el resumen) — el
refresh entre días queda en 2 pasos (transmitir → obtener información).
"Cerrar rueda" sigue para cambiar de rueda sin re-descargar. Validado en uso
real por el propio usuario (purgó 6) y con tests (46/157). Trampa recurrente
confirmada: un rueda-api VIEJO dueño de :4568 sirvió un export sin
people/supplier_ids → membresías en 0; matar pumas huérfanos antes de probar.

