# memory — rueda-negocios

Bitácora de decisiones y contexto del proyecto. Se actualiza conforme
avanzamos (paso **Documentar** del flujo PAIVD).

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

## Estado actual

Estructura de repos definida; ambos en GitHub (org **ercom-tech**):
`ercom-tech/rueda-negocios` y `ercom-tech/rueda-api`, rama `master`.
**Descubrimiento del esquema del ERP COMPLETADO** (contra BD dev `fecego` @1702):
catálogos/sync-down → `docs/erp-esquema-catalogos.md`; **pedidos/sync-up (alta)**
→ `docs/erp-esquema-pedidos.md`.

**Fase A COMPLETADA** (app `rueda-negocios`): `rails new` + modelos del dataset
local, migrado y validado.

**Fase C/D — sync completo VALIDADO end-to-end contra el ERP dev:**
- **sync-down:** export en rueda-api (`GET /ruedas/:id/export`) + `rake sync:down`
  (replace del catálogo, deja la BD local idéntica al export).
- **sync-up:** alta de pedidos en rueda-api (`POST /pedidos`, folio + idempotencia)
  + `rake sync:up` (transmite pedidos, guarda `erp_folio`/`transmitted_at`).
- **Pendiente con FECEGO:** confirmar los defaults de config de la cabecera
  (ya escritos con la moda del ERP en `OrderCreate::HEADER_DEFAULTS`).

**Fase B — LOGIN, MENÚ, hub de REPORTES y PEDIDO completo**: autenticación
(bcrypt) + login; **menú** (`home#index`); **hub de reportes** (`reports#index`,
`/reports`); y el **pedido completo** — encabezado (`orders#new`, paso 1),
**detalle** (`orders#show`, paso 2) y **resumen/envío** (`orders#summary`, paso 3).
Diseños desde `docs/design-reference/{login,menu,reportes,pedidos}`.

## Decisiones tomadas

- **Forma de trabajo:** flujo PAIVD. No edit/write sin aprobación previa del
  usuario en el turno.
- **Proyecto independiente:** no aditivo al b2b; b2b es solo referencia.
- **Arquitectura:** una laptop = servidor LAN; app + Postgres local; los
  demás equipos apuntan por navegador. Offline resuelto a nivel de red.
- **App (`rueda-negocios`):** Rails 8 + Hotwire + Tailwind + Postgres + bcrypt.
- **API (`rueda-api`):** Sinatra + Sequel + pg contra la BD del ERP; expone
  export del dataset + creación de pedidos en el ERP.
- **Sync desde la oficina** (antes/después del evento) por defecto; evento
  100% offline.
- **Sync transporte-agnóstico:** LAN o internet configurable (URL + token).
  Seguridad/hardening → fase posterior de strengthening (diferido).
- **IDs de pedido:** UUID local generado offline; folio ERP se asigna al
  transmitir; se guarda el mapeo. Transmisión idempotente y reintentable.
- **Estructura: dos repos separados** (convención b2b, uno por deployable):
  - `_fecego/rueda-negocios/` — app Rails de la laptop; incluye las rake
    tasks de sync (down/up). No hay repo de sync aparte.
  - `_fecego/rueda-api/` — API Sinatra on-prem (plantilla api-v2).
  - Contrato compartido (JSON de export + alta de pedidos): documentado en
    `docs/erp-esquema-catalogos.md` y `docs/erp-esquema-pedidos.md` (este repo).
    (El `rueda-api/docs/contract.md` planeado nunca se creó — 2ª auditoría M9.)
- **Ignorado:** `_fecego/offline/local.sqlite` (spike previo, no forma parte
  del proyecto).

### Descubrimiento del esquema de catálogos (ERP) — decisiones

Detalle completo en `docs/erp-esquema-catalogos.md`. Puntos duros:

- **BD:** `psql -p 1702 -d fecego` (Postgres.app), esquema `fecego`.
- **`id_empresa = 1` siempre.** Toda PK arranca con `id_empresa`; borrado
  lógico con `baja = false`.
- **La rueda ya existe nativa en el ERP** (6 tablas `cnf_rueda_negocios*`):
  cabecera + proveedor/marca/vendedor/cliente/persona. No es concepto nuevo.
- **Mapa de entidades:** clientes=`vta_cliente`, login=`cnf_persona` +
  `cnf_persona_has_metodoidentifica` (¡sin guion bajo!), vendedores=
  `vta_vendedor` (→`cnf_persona` vía `id_persona`), proveedores=
  `com_proveedor`, marcas=`com_marca` (NO `cnf_marca`), productos=
  `com_producto`, precios=`com_producto_has_precio`.
- **SKU oficial de FECEGO = `com_producto.id_producto`** (la PK). NO usar
  `com_producto_has_sku` como código oficial (ese es el SKU del proveedor).
- **Login SIEMPRE** vía `cnf_persona`/`cnf_persona_has_metodoidentifica`,
  nunca `vta_vendedor`.
- Relación producto→marca directa (`com_producto.id_marca`); producto→
  proveedor por puente (`com_proveedor_has_producto`).

### Fase A — scaffolding app `rueda-negocios` (decisiones)

- **Toolchain:** Ruby **3.3.7** (rbenv, `.ruby-version`, igual que el servidor
  y b2b), Rails **8.1.3**, Postgres **17** local en **puerto 1702** (Postgres.app,
  rol `fecego`, mismo cluster que b2b). Bases propias `rueda_negocios_{development,test}`.
- **Stack:** Rails 8 + Hotwire (importmap) + Tailwind + pg + bcrypt + dotenv-rails.
  `database.yml` parametrizado por ENV (`.env`, gitignored; `.env.example` versionado).
- **Modelos en inglés, diseño limpio:** se descarta la estructura del ERP
  (sin `id_empresa`, sin auditoría). Cada tabla preserva su llave de negocio del
  ERP como `erp_*` con índice único (para upsert del sync y mapeo de identidad).
- **Entidades:** `User`, `BusinessRound`, `Salesperson`, `Client`, `Supplier`,
  `Brand`, `Product`, `Price` + uniones `ProductSupplier`, `BusinessRoundClient`
  y puentes HABTM (brands_suppliers, business_round_{suppliers,brands,salespeople}).
- **Producto (según requerimiento):** Código FECEGO (`erp_product_id`),
  descripción, número de parte, unidad, marca, **mínimo de venta**, **descuento
  tope**, existencia. **Proveedores y SKUs de proveedor** → modelo de unión
  `ProductSupplier` (con `supplier_sku`), no HABTM puro.
- **Price:** un solo registro activo por producto (índice único en `product_id`),
  reducido a **precio público + mayoreo** (lo que pide el requerimiento).
- **Login (Fase B):** `has_secure_password` NO cableado; `User.password_hash`
  guarda el hash del ERP. Falta confirmar el algoritmo (¿bcrypt?) antes de
  implementar `authenticate` — el `varchar(256)` del ERP sugiere que podría no
  ser bcrypt. [[erp-esquema-catalogos]]

### Fase B — arco login (decisiones)

- **Hash del ERP es bcrypt** (confirmado por el usuario) → columna renombrada a
  `password_digest` y `has_secure_password validations: false` en `User`. Se
  valida directo sin re-hashear; `validations: false` porque el usuario entra
  por sync (solo trae el digest), nunca se fija contraseña desde la app.
- **Sesión** por `session[:user_id]`; `SessionsController` (layout `auth`),
  `require_login` global en `ApplicationController`, `reset_session` en
  login/logout. Usuarios inactivos no entran.
- **Diseño:** tomado de `docs/design-reference/login`. Assets copiados a
  `app/assets/images` con nombres propios: `fecego_logo_white.png`,
  `tools_pattern_white.svg` (era `13.svg`; el `12.svg` es la versión negra),
  `event_card_oaxaca.svg` (tarjeta del evento; luego dinámica por rueda).
  Regla del usuario: **al copiar assets, renombrarlos con nombre adecuado**.
- **Paginación:** gem `pagy` agregado (aún sin uso; para los listados futuros).
- **Seed dev** (`db/seeds.rb`, solo development): rueda activa Oaxaca 2026 +
  usuario `capturista` / `rueda2026`. Placeholder hasta el sync real (Fase D).
- **Placeholder post-login:** `HomeController#index` (destino de login) — mínimo,
  se reemplaza cuando lleguen las pantallas de navegación.
- **Tests:** `test/integration/authentication_flow_test.rb` (5 casos, verdes).

### Fase B — arco menú (decisiones)

- **`home#index` = menú** ("¿Qué quieres hacer hoy?"), landing autenticado.
  Usa el layout `auth` (shell oscuro full-bleed, reusado del login).
- **4 opciones** (= arcos futuros): Registrar pedido (tarjeta coral), Reportes
  de venta, Asistencia de clientes, Generar cotización (amarillas). Partial
  `home/_menu_card`. Hoy enlazan a `#`; se cablean cuando se construya cada una.
- **Assets** copiados a `app/assets/images` con nombres propios: `expo_illustration.svg`
  e `icon_{register_order,sales_reports,client_attendance,generate_quote}.svg`.
- **Barra superior:** logo + pills `Usuario` (real, `current_user`) y `Proveedor`
  + `Cerrar sesión`.
- **Proveedor del capturista** (pill) — RESUELTO: modelado con
  `BusinessRoundPerson` (mapea `cnf_rueda_negocios_persona`, tabla
  `business_round_people`): liga `User` (persona) ↔ `Supplier` ↔ `BusinessRound`
  (+ marca opcional, `position` = el `consecutivo` del ERP).
- **Multi-proveedor:** un capturista puede representar a **varios** proveedores
  (el ERP lo permite vía `consecutivo` → local `position`). `User#suppliers_in(round)` devuelve
  todos. Se maneja con un **proveedor activo por sesión** (`session[:supplier_id]`):
  helpers `active_round` / `available_suppliers` / `current_supplier` en
  `ApplicationController`; 1 proveedor → autoselección, >1 → **selector** en el
  pill (`shared/_supplier_pill`, controller Stimulus `form-submit`, ruta
  `PATCH /active-supplier` → `ActiveSuppliersController`).
  **Hoy el proveedor activo es solo contexto/etiqueta: NO restringe la captura**
  (un pedido puede mezclar proveedores). Regla a definir si cambia.
- **Seed dev:** liga al capturista con 2 proveedores (Hitools, Truper) para
  probar el caso multi.

### Fase B — hub de reportes (decisiones)

- **`ReportsController#index`** en `/reportes` (layout `auth`; hoy `/reports`). La card
  "Reportes de venta" del menú enlaza aquí.
- **Patrón de pantalla interna:** header amarillo full-width (título + logo que
  regresa al menú; logo blanco con `invert` sobre el amarillo) + cuerpo negro
  con patrón + contenido centrado. Minimalista (sin pills de usuario/proveedor
  ni logout, por decisión del usuario).
- **4 sub-reportes** (tarjetas cuadradas amarillas, partial `reports/_report_card`):
  Pedidos capturados, Reporte de asistencia, Reporte de productos, Reporte de
  ventas. Enlazan a `#` (cada reporte se construye después).
- Íconos negros uniformes vía `brightness-0` (el asset de "ventas" venía coral).
  Assets: `icon_{captured_orders,attendance_report,products_report,sales_report}.svg`.

### Fase B — Pedido, Arco 1 / encabezado (decisiones)

- **`Order`** (borrador): belongs_to user (capturista) / business_round / client.
  **NO lleva proveedor** — un pedido puede mezclar productos de varios
  proveedores; el proveedor activo es solo contexto de sesión. `kind`
  (invoice/remission), `status` (draft/submitted; hoy draft/captured/transmitted),
  `erp_folio` (nulo hasta sync).
- **Datos fiscales del cliente** (nuevos modelos): `ClientTaxProfile` (RFC +
  razón social + uso CFDI default), `ClientReceiptProfile` (remisión),
  `ClientBranch` (sucursal), `CfdiUse` (catálogo SAT), `Client.email`. Todos con
  `erp_*` para el sync (mapeo fino con el ERP se valida en el arco de sync).
- **Paso 1 (`orders#new`):** tema **claro/crema** (patrón negro `tools_pattern_black.svg`,
  copiado de `12.svg`), header amarillo. Dos paneles: "Datos del cliente"
  (clave → carga; Factura/Remisión con toggle Stimulus `order-kind`; CFDI; RFC/
  razón social; dirección) y "Catálogo de clientes" (busca por nombre → clave/
  nombre/vendedor). Defaults: is_default o primero; CFDI = default del RFC.
- **Validación** en `Order` (`header_selections_present`): Factura exige RFC +
  CFDI; Remisión exige remisión (si hay); sucursal obligatoria si el cliente
  tiene. Al guardar → `orders#show` (resumen; placeholder de paso 2).
- La card "Registrar pedido" del menú enlaza a `orders#new`.
- **Seed:** 2 clientes demo — C0001 (2 RFC, 2 sucursales) y C0002 (uno de cada)
  — + catálogo CFDI (G01/G03/P01) + vendedor.

### Fase B — Pedido, Arco 2 / detalle (decisiones)

- **`OrderItem`** (partida): snapshot de código/descripción/no.parte/unidad/precio/
  IVA (`tax_rate`) del producto al agregarlo. `position` = consecutivo. Line total
  = cantidad × precio (descuento e IVA se aplican al agregado, como la referencia).
- **Datos nuevos:** `Product.model` (modelo, para búsqueda), `Price.tax_rate` (IVA,
  del ERP `com_producto_has_precio.iva`), `Order.observations`.
- **Totales en `Order`:** subtotal=Σ(cant×precio); descuento=Σ(línea×%); **IVA=
  Σ(base×tax_rate del producto)**; total=subtotal−descuento+IVA. (Los números de
  `paso2.png` eran ilustrativos; se validará el manejo fiscal exacto en el sync.)
- **Búsqueda de producto** (`Product.search`): código FECEGO (`erp_product_id`),
  código proveedor (`product_suppliers.supplier_sku`), nombre (`description`),
  modelo, número de parte.
- **Pantalla `orders#show`** (paso 2, tema claro): resumen del encabezado + buscador
  de producto con autocompletado + tabla de partidas (todas las columnas, bordes
  redondos, borrar por fila, editar cantidad/descuento en línea) + totales +
  observaciones. **Interacciones vía Turbo Streams** (`OrderItemsController`
  create/update/destroy → reemplaza `#order-detail`). Auto-guardado de observaciones.
- Botones: **Editar** → paso 1; **Cancelar** → menú (turbo_confirm); **Enviar** →
  `#` (Arco 3). (Superado: hoy Cancelar abre un modal accesible que DESCARTA el
  borrador —`Orders#destroy`, M15— y el botón final es "Guardar" → `capture`.)
- **Seed:** 5 productos demo (con precio, IVA 16%, modelo, No. parte, SKU proveedor).

### Fase B — Pedido, Arco 3 / envío + resumen (decisiones)

- **`Order.submit!`** (hoy `capture!` → `status: captured`): exige ≥1 partida + asigna
  **`local_folio`** (`RN-000123`, offline; el `erp_folio` llega en el sync).
  `Order#folio` = local o erp.
- **`orders#submit`** (hoy `orders#capture`, botón "Guardar") → **`orders#summary`** (paso 3).
- **Paso 3 (`summary`)**: panel "Resumen del pedido" con folio + 3 opciones
  (Generar PDF / Enviar por correo / Enviar por WhatsApp) + Terminar (→ menú).
- **Enviar por correo = MODAL** (Stimulus `modal`): correo registrado + input para
  otro. (Superado: hoy correo/WhatsApp son placeholders deshabilitados
  "Próximamente" —M7 de la 1ª auditoría—; el modal se retiró.)
- **Generar PDF:** implementado con **prawn** (`Pdf::OrderGenerator`, offline).
  **Replica el formato IMPRESO del ERP** (muestras `PedidoKE*.pdf` del b2b, en
  `portal-v2/tmp/letter_opener`): logo fecego + datos de empresa, "PEDIDO" +
  CLAVE/Fecha, bloque cliente (POR FACTURAR/RFC/razón social o remisión) +
  atributos (capturado/transmitido/vendedor/estatus), tabla con bordes
  (Código/Descripción/Unidad/Cantidad/Precio/Monto/%Dto./Subtotal/%IVA/Total),
  **importe en letra** (conversor español propio) y totales. `orders#pdf` →
  descarga. Íconos `icon_{pdf,mail,whatsapp}.svg`.
- **Logo oscuro:** `fecego_logo_dark.png` = `logo_fecego.png` del b2b (blanco)
  invertido a negro (con chunky_png, una vez) para el PDF en fondo blanco.
- **Diferido:** envío por **correo** real (SMTP; offline se difiere al sync) y
  **WhatsApp** (stub). Los botones existen y responden.

### Fase B — reporte "Pedidos capturados" + roles (decisiones)

- **Rol en `User`** (enum `role`: `capturista` | `server`, default capturista).
  `User#can_see_all_orders?` = `server?`. Mapeo fino con el ERP (`cnf_persona.id_rol`)
  se define en el sync.
- **Regla validada (importante para rueda-api / uso real):** un **capturista ve
  solo SUS pedidos** (`current_user.orders`); el **equipo-servidor ve TODOS**
  (`Order.all`) — para transmitirlos al ERP. `ReportsController#captured_orders`
  (`/reportes/pedidos-capturados`, hoy `/reports/captured-orders`, card del hub) con badge "Mis pedidos" /
  "Todos los pedidos".
- **Seed:** usuarios `servidor` (rol server) y `capturista2`, + un pedido de
  capturista2 para demostrar el scoping. Ambos con `rueda2026`.

### Fase C — `rueda-api` export / sync-down (decisiones)

- **Endpoint único:** `GET /ruedas/:id/export` → arma TODO el dataset de la
  rueda en un solo JSON (`RuedaApi::Export.for_rueda`). Acotado a `id_empresa=1`
  y a la rueda. Validado con Oaxaca (`id_rueda=3`): 200, ~3.6 MB, **47 clientes,
  15 vendedores, 3 usuarios, 24 usos CFDI, 18 proveedores, 1 marca, 13,196
  productos**.
- **Llaves del JSON** (las que consumirá el sync-down): `round`, `cfdi_uses`,
  `users`, `salespeople`, `suppliers`, `brands`, `clients` (con `tax_profiles`/
  `receipt_profiles`/`branches` anidados vía `jsonb_agg`), `products` (con
  `supplier_skus` y precio/IVA/tope embebidos).
- **Scope de productos:** unión **marca ∪ proveedor** participante de la rueda
  (`p.id_marca IN marcas` OR `EXISTS com_proveedor_has_producto IN provs`).
- **Scope de clientes:** solo los **registrados en la rueda**
  (`cnf_rueda_negocios_cliente`), no todo el padrón.
- **Precio:** primer renglón vigente de `com_producto_has_precio` (LATERAL,
  `ORDER BY consecutivo LIMIT 1`) → `public_price`/`wholesale_price`/`tax_rate`/
  `max_discount`.
- **`description` del producto = `com_producto.nombre`** (decisión del usuario;
  no `nombre_publico`/`descripcion_corta`). **Unidad = `cnf_unidad_medida.
  abreviacion`** (no existe `clave`).
- **Decimales:** el ERP devuelve NUMERIC como `BigDecimal` y la gema `json` lo
  serializa en notación científica (`"0.47108e3"`). Se resolvía con `deep_coerce`
  → **string decimal plano** (`"471.08"`); rueda-negocios lo castea a `decimal`.
  NO usar Float para montos. (Superado: hoy el cast va en SQL con
  `trim_scale(...)::text` y `deep_coerce` no existe — Grupo B de los BAJA.)
- **`baja = false` en TODO:** los catálogos principales ya filtraban; se agregó
  también en las **7 tablas puente** (`cnf_rueda_negocios_*`,
  `com_proveedor_has_producto`, `com_producto_has_sku`). Sin esto se colaban
  relaciones dadas de baja (p.ej. SKUs muertos en `supplier_skus`).
- **Trampa de validación:** un server viejo (previo a la ruta) puede quedar
  ocupando el puerto → `rackup` nuevo falla el bind silenciosamente y el viejo
  responde 404 al endpoint nuevo. Matar procesos `puma`/`rackup` huérfanos antes
  de probar.

### Fase D — rake `sync:down` en `rueda-negocios` (decisiones)

- **`rake sync:down`** (`lib/tasks/sync.rake`) → `Sync::Down`
  (`app/services/sync/down.rb`). Baja `GET {RUEDA_API_URL}/ruedas/{RUEDA_ID}/export`
  con `Net::HTTP` (stdlib, sin gema nueva) y puebla el Postgres local dentro de
  una transacción. ENV `RUEDA_API_URL` + `RUEDA_ID` en `.env`.
- **Estrategia = REPLACE, no merge** (decisión del usuario). Es un *refresh
  pre-evento*: deja el catálogo local **idéntico al export**. Borra el catálogo
  (hijos→padres, respetando FKs; vacía también las tablas de membresía aún no
  usadas) y reinserta con `insert_all`. Validado: totales en BD == export exacto,
  0 residuo.
- **Guarda:** `Sync::Down::GuardError` si `Order.exists?` → el rake **aborta**
  con mensaje. El sync-down no debe correr sobre pedidos ya capturados (evita
  romper FKs / perder captura). Validado.
- **Usuarios = excepción al replace:** merge por `erp_person_id` **sin tocar
  `role`** + cleanup de capturistas que ya no vienen del ERP. **Nunca borra un
  `server`.**
- **Rol `server` = usuario SEEDEADO** (decisión del usuario, sobre promoción).
  `db/seeds.rb` ahora crea SOLO ese usuario, con identidad sintética
  `erp_person_id = 0` (reservado app; el ERP nunca usa 0) para que el cleanup lo
  preserve siempre. Credenciales por ENV `SEED_SERVER_USERNAME`/
  `SEED_SERVER_PASSWORD` (fallback dev `servidor`/`rueda2026`). El resto del
  dataset (rueda/clientes/productos/capturistas) YA NO se seedea → viene por
  `sync:down`. En dev: `db:reset` (crea server) + `sync:down` (puebla catálogo).
- **Migración `users.prefix`** (`20260725073308`): guarda el prefijo del ERP
  (`cnf_persona.prefijo`, p.ej. "1A") que necesita el folio del sync-up.
- **SKUs de proveedores fuera de la rueda:** se omiten (no hay proveedor local);
  el rake reporta el conteo. Con Oaxaca: 0 omitidos.
- **`record_timestamps: true`** en `insert_all`/`upsert_all` para que Rails
  llene `created_at`/`updated_at`.

### Fase D — sync-up (alta de pedidos en el ERP) (decisiones)

- **rueda-api `POST /pedidos`** (`RuedaApi::OrderCreate`) inserta en
  `fecego.vta_pedido` + `vta_pedido_detalle` y devuelve `clave_pedido`. Todo en
  una transacción con `pg_advisory_xact_lock(hashtext(prefijo))` para serializar
  la asignación de folio por prefijo.
- **Folio** = prefijo del capturista (`cnf_persona.prefijo` vía `id_persona`) +
  consecutivo (`MAX(substring(clave_pedido FROM 3)::int)+1`, filtrando
  `~ '^[0-9]+$'` para no reventar el cast), a 4 dígitos.
- **Idempotencia:** antes de insertar busca por la PK de negocio
  `(id_empresa, clave_cliente, fecha_pedido, hora_pedido)`; si existe, devuelve
  su folio con `idempotent:true` sin reinsertar. Validado por ambos lados.
- **Defaults de config ESCRITOS** (moda de ~486k pedidos transmitidos; PENDIENTE
  confirmar con FECEGO, se ajustan en `HEADER_DEFAULTS`): `c_FormaPago="99"`,
  `c_MetodoPago="PPD"`, `condicion_pago="50"`, `tipo_precio="MA"`,
  `id_negociaciontipo=1`, `id_enviotipo=1`, `estatus_actual="CAPTUR"`.
  `id_vendedor` = el del cliente; `id_usuario_crea/transmision` = erp_person_id
  del capturista; `transmitido=true`.
- **rueda-negocios `rake sync:up`** (`Sync::Up`): toma `Order.captured` sin
  `erp_folio`, hace POST, y al éxito guarda `erp_folio` + `transmitted_at`
  (columna nueva, migración `20260725153508`). Idempotente: no re-transmite lo
  que ya tiene folio.
- **Hora de captura:** `created_at.localtime` → `fecha_pedido`/`hora_pedido` (el
  ERP maneja horas locales; `created_at` es UTC). Estable → sirve de llave de
  idempotencia.
- **`id_producto` del detalle** = `order_item.product.erp_product_id`.
- **Trampa Sequel:** `Sequel.function(:current_time)` emite `current_time()` con
  paréntesis → error en PG; usar la constante `Sequel::CURRENT_TIME` (y
  `Sequel::CURRENT_DATE`). Y al usar heredoc `<<~SQL` en `DB.fetch`, TODOS los
  args van en la misma línea física del `<<~SQL` o Ruby se los come como cuerpo.
- **Validado end-to-end** contra el ERP dev: pedido factura (cliente ABAISM,
  capturista makita1/prefijo 1A) → folio `1A0016`, cabecera+detalle correctos,
  IVA por partida, totales cuadran; idempotencia confirmada; pedido de prueba
  limpiado del ERP.

### Fase D — Panel del servidor (UI de sync) (decisiones)

- **El rol `server` opera el sync desde la UI** (antes solo rakes). Al entrar el
  servidor ve, en el mismo menú (`home#index`, bifurcado por rol), 3 tarjetas:
  **Elegir rueda**, **Obtener información** (sync-down) y **Transmitir pedidos**
  (sync-up) + Reportes. El capturista sigue viendo su menú de captura.
- **Decisiones del usuario:** ejecución en **background job** (no bloquear);
  **tarjetas en el mismo menú** (no panel separado); el `server` es **seedeado**
  (ya existente) y su rol se preserva.
- **rueda-api `GET /ruedas`** (`RuedaApi::Rounds`) — lista las ruedas del ERP
  para elegir cuál trabajar.
- **rueda-negocios:**
  - `Setting` (singleton local): `selected_round_erp_id` + `selected_round_name`
    (guarda el nombre al elegir, para mostrarlo sin depender del sync).
  - `SyncRun` (kind down/up, status running/completed/failed, summary jsonb):
    historial/estado de cada sync. `after_update_commit` hace **broadcast Turbo
    Stream** al stream `"sync_status"` → el menú se actualiza en vivo al terminar
    el job (sin recargar).
  - `Sync::ApiClient` (antes `Sync::Client` — **renombrado** porque `Client`
    colisiona con el modelo dentro de `module Sync`): `list_rounds`,
    `fetch_export`. Reusado por rake y jobs.
  - Jobs `SyncDownJob` / `SyncUpJob`: crean/cierran el `SyncRun`, corren
    `Sync::Down`/`Sync::Up`. `solid_queue` en prod (corre dentro de Puma con
    `SOLID_QUEUE_IN_PUMA`); `async` en dev.
  - Guarda `require_server` + `ServerController` (rounds, select_round,
    sync_down, sync_up). Evita disparar un sync si ya hay uno `running`.
- **Validado end-to-end en el navegador** (rueda-negocios en :3001 con
  `RUEDA_API_URL`, rueda-api en :4568): login server → elegir Oaxaca → obtener
  información (job → "✓ Listo · 13,196 productos…" vía Turbo Stream) → transmitir
  (job → "✓ Listo · 0 pedidos").
- **Trampa de layout:** `turbo_stream_from` renderiza un
  `<turbo-cable-stream-source>` que, si cae dentro de un grid, cuenta como celda
  y descuadra el layout. Va FUERA del grid (en `home/index`, antes de la barra);
  el partial del menú server es un solo `<div>` (la columna derecha), igual que
  el del capturista. Las cards usan un **grid de columnas fijas**
  (`grid-cols-[3.5rem_11rem_minmax(0,1fr)]`: icono·título·desc) para alinear
  título/descripción entre sí pese a mezclar `link_to` y `button_to` (el `<form>`
  del button descuadra un layout basado en `flex`). Íconos Heroicons (outline),
  coloreados con `currentColor` según la card.
- **Trampa:** `allow_browser versions: :modern` (ApplicationController) bloquea
  con 403 las sesiones de `ActionDispatch::Integration` (UA no reconocido) — no
  es bug; validar la UI con navegador real o request specs con UA moderno.

### Estatus del pedido — captured / transmitted (decisiones)

- **Enum `status` = `draft → captured → transmitted`** (reemplaza `submitted`).
  `draft`=Borrador (en captura), `captured`=Capturado (finalizado por el
  capturista, **editable**), `transmitted`=Transmitido (ya en el ERP, **NO
  editable**). Migración de datos `20260725184048` (submitted→captured; y
  →transmitted si tenía erp_folio).
- **`Order#submit!` → `capture!`** (pone `status: captured`). El botón del paso 2
  (`orders/show`) dice **"Guardar"** (antes "Enviar"); mensajes ajustados.
- **`capture` sigue editable hasta transmitir** (decisión del usuario); solo
  `transmitted` bloquea. `Order#editable? = !transmitted?`.
- **Bloqueo de edición** (backend + UI): `OrderItemsController` before_action
  `ensure_editable` (403) y guardas en `orders#capture`/`observations`. En
  `orders/show`, si no es editable se ocultan buscador, controles de partida
  (cantidad/descuento/borrar → texto plano) y observaciones (solo lectura);
  acciones = solo "Ver PDF" + "Volver al menú".
- **Transmisión (sync-up):** selecciona `Order.captured.where(erp_folio: nil)` y
  al transmitir pone `status: "transmitted"` (+ `erp_folio` + `transmitted_at`).
- **Etiquetas** (`Order#status_label` = Borrador/Capturado/Transmitido) usadas en
  el reporte (badge de color por estado), el PDF (`Estatus:` + `Transmitido:`
  usa `transmitted_at`) y `orders/show`.
- Validado en navegador: captura muestra "Guardar"/"Capturado" editable;
  transmitido queda de solo lectura.

## Riesgos / puntos abiertos

- **Empaquetado / deployment del "servidor" (PENDIENTE definir)** — cómo instalar
  la app en el equipo del evento y servirla en la LAN. Análisis:
  - **El proyecto ya tiene** `Dockerfile` (producción), `bin/docker-entrypoint`,
    `.dockerignore` y `config/deploy.yml` (Kamal). Falta un `docker-compose.yml`
    (app + Postgres) para el modo "todo en un equipo".
  - **Windows:** Docker Desktop (requiere WSL2, con fricción) o VM Linux como
    plan B. Ruby/Postgres nativo en Windows: frágil, **desaconsejado**.
  - **Linux (preferido; encaja con la infra Linux de FECEGO):**
    - **Docker Compose** + `restart: unless-stopped` → reproducible, portable,
      auto-arranque al boot. **Recomendado.**
    - **Nativo + systemd** (Ruby por rbenv/asdf + Postgres del sistema, Puma con
      `SOLID_QUEUE_IN_PUMA`) → más ligero pero menos portable entre distros.
  - **A resolver al empacar:** `RAILS_ENV=production` (SECRET_KEY_BASE/master key,
    assets precompilados, `config.hosts` para la IP de la LAN); persistencia
    (volumen Postgres + `pg_dump` a USB); **offline** (pre-descargar las imágenes
    Docker en la oficina); primer arranque (`db:prepare` + seed del server +
    `sync:down`).
  - **Decisión pendiente:** plataforma (Windows/Linux) y método (Docker Compose
    vs nativo/systemd). Parte de la fase de deployment/strengthening.


- **Entrada de pedidos al ERP (sync-up)** — DESCUBIERTO → `docs/erp-esquema-pedidos.md`.
  El ERP inserta en `fecego.vta_pedido` (cabecera, PK `id_empresa/clave_cliente/
  fecha_pedido/hora_pedido`) + `vta_pedido_detalle`. Ya existe el patrón de
  **pedidos de ruta transmitidos** (`transmitido`, `clave_pedido_ruta`) — la rueda
  encaja ahí. **Folio `clave_pedido` se asigna EN LA TRANSMISIÓN** (prefijo del
  `cnf_persona` del capturista + consecutivo = último con ese prefijo +1) → `erp_folio`.
  `estatus=CAPTUR`; `id_vendedor` = el del cliente; `bodega` sin uso;
  `clave_pedido_ruta` NO es nuestro (lo llena la planeación de ruta de FECEGO).
  IVA por partida confirmado. Idempotencia del reintento **RESUELTA**
  (`OrderCreate.find_existing` por la PK de negocio). **Pendiente:** solo los
  campos de config (`c_FormaPago`/`c_MetodoPago`/`condicion_pago`/`tipo_precio`/
  `id_negociaciontipo`/`id_enviotipo`), a confirmar con FECEGO.
- **Punto único de falla:** la laptop-servidor. Definir backups (pg_dump a
  USB/otro equipo) y quizá laptop de respaldo.
- **Origen de precios/beneficios de la rueda:** RESUELTO el hallazgo — el ERP
  **no** tiene precios ligados a `id_rueda`. Los precios viven en el catálogo
  general `com_producto_has_precio` (niveles mayoreo/público/intermedio/crédito
  + `factor_descto1..5`). El "precio especial por rueda" es concepto a definir
  en la app (modelo propio con FK `id_rueda`+`id_producto`, o reúso del
  catálogo). Decisión diferida.
- **LAN del evento:** IP fija + hostname (mDNS `laptop.local`), router
  dedicado. Por definir.
- **Seguridad/limpieza:** la laptop lleva datos de clientes y precios →
  cifrado de disco + limpieza post-evento. (Parte del strengthening.)

## Próximos pasos

1. **Confirmar con FECEGO** los defaults de config de la cabecera del pedido
   (ya escritos en `OrderCreate::HEADER_DEFAULTS` con la moda del ERP) y si
   alguno debe salir del cliente en vez de ser fijo.
2. **Fase B (resto)** — pantallas read-only pendientes (productos, clientes,
   rueda activa) y otras del menú (asistencia de clientes, cotización).
3. **Membresía de rueda en el export/sync** — `business_round_people`
   (capturista↔proveedor/marca), `brands_suppliers`, `business_round_*`. Hoy el
   export no las trae y el sync-down solo las vacía. Definir cuando la UI las
   necesite (p.ej. `suppliers_in` del capturista).
