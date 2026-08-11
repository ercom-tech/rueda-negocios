# memory — rueda-negocios

**Bitácora de decisiones y su porqué.** Se consulta cuando hace falta entender
por qué algo está como está, o recuperar el contexto de un cambio viejo. Se
escribe en el paso **Documentar** del flujo PAIVD.

## Dónde va cada cosa

| Archivo | Contenido | ¿Se carga solo? |
|---|---|---|
| `CLAUDE.md` | Contrato del proyecto: forma de trabajo, arquitectura, stack | Sí |
| `docs/convenciones-visuales.md` | Normas de UI y de los textos al usuario | Sí (import) |
| `docs/convenciones-codigo.md` | Normas y trampas del stack | Sí (import) |
| **`memory.md`** | **Bitácora: decisiones y su porqué** | **No — se consulta** |
| `backlog.md` | Lo que falta implementar | No — se consulta |
| `docs/erp-esquema-*.md` | Esquema del ERP (catálogos y pedidos) | No — se consulta |
| `docs/auditorias-2026-07.md` | Historial de las 2 auditorías (cerradas) | No — archivo |

Regla práctica: si es **norma que debe regir cada cambio**, va a las
convenciones (que sí se cargan). Si es **el porqué de una decisión**, va aquí.
Si es **algo por hacer**, va al backlog.

## Índice de la bitácora

- Decisiones generales del proyecto (abajo)
- Descubrimiento del esquema de catálogos (ERP)
- Fase A — scaffolding · Fase B — login, menú, reportes, pedido (arcos 1–3)
- Fase C — `rueda-api` export / sync-down
- Fase D — rake `sync:down`, sync-up, panel del servidor, estatus del pedido

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
- **Consecutivo sin huecos (2026-08-10):** borrar una partida intermedia dejaba
  hoyos en la columna Consecutivo. `Order#renumber_items!` reacomoda a 1..N y
  se llama desde `OrderItems#destroy`. Usa `update_column`: no es un cambio de
  negocio sino de orden, y una partida con algún problema previo no debe
  bloquear la renumeración del resto. Alcance real medido antes de tocar nada:
  `position` **solo se muestra** en esa columna — el PDF no la lleva y el
  payload del sync-up ya numera `1..N` con `with_index(1)`, así que el ERP
  nunca vio huecos.
- **Tope de 45 partidas por pedido (2026-08-10):** regla de **negocio** de la
  rueda, NO del ERP — medido: el histórico del ERP llega a 287 renglones y
  tiene 3,177 pedidos con más de 45. El usuario confirmó que la regla opera
  hoy y que **puede subir cuando entren los regalos por promoción**; y que
  aplica solo a partidas (renglones), nunca a cantidades. Implementación:
  - `Order::MAX_ITEMS = 45` + `Order#items_count_for_limit` /
    `#items_limit_reached?` — **punto único** de la regla. Cuando lleguen los
    regalos, ahí se decide si se excluyen del conteo o si solo sube la
    constante, sin perseguirla por modelo/controlador/vista.
  - Validación en `OrderItem` **`on: :create`**: un pedido que ya rebase el
    tope (si la regla bajara) sigue siendo editable — se pueden corregir
    cantidades y quitar renglones — en vez de quedar atorado. Va en el modelo
    y no solo en el controlador: cubre POST forjado (validado en navegador:
    rebota con el aviso aunque el buscador esté deshabilitado). No hubo que
    tocar `OrderItemsController#create`: su rama `else` ya muestra
    `errors.full_messages` en el flash.
  - UI: contador `Partidas 12 / 45` siempre visible **dentro del buscador**, al
    extremo derecho del pill (decisión del usuario; primero se probó como
    encabezado de la tabla y arriba del buscador), y buscador deshabilitado con
    placeholder "Alcanzaste el máximo de 45 partidas". El **60%** de
    deshabilitado va sobre el control (lupa + campo) y NO sobre el pill
    completo: el contador es información, no control, y debe quedar legible
    justo cuando se alcanza el tope. El buscador se extrajo a
    `orders/_product_search` con id propio y se repinta con **morph** en
    `detail_streams` — con `replace` se reconectaría el controlador Stimulus,
    que al conectar enfoca el buscador, y le robaría el foco a la tabla en cada
    edición de cantidad/descuento (validado: el foco se queda en el input).

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
- **Resumen por estatus + paginador (2026-08-10):**
  - El paginador ya existía (25 por página) pero se **ocultaba con una sola
    página**, así que en desarrollo parecía no existir. Ahora el conteo se
    muestra siempre —saber cuántos hay es dato útil por sí mismo— y la
    navegación aparece solo cuando hace falta. Se agregaron números de página
    con elipsis (`@pagy.series`) y selector de 25/50/100 (lista cerrada: por
    URL nadie debe pedir 5,000 renglones). Partial `shared/_paginator`,
    reutilizable.
  - **Los enlaces se arman con `request.query_parameters.merge`**, no solo con
    `page:`: así los filtros que vienen en el backlog sobrevivirán al paginar
    sin tocar el partial.
  - **Resumen ARRIBA de la tabla, no dentro del paginador** (decisión
    discutida con el usuario): son dos trabajos distintos —el paginador dice
    dónde estás en el listado, el resumen cómo va el conjunto— y juntos se
    leería ambiguo ("¿este total es de la página o de todo?"). Además el
    paginador se oculta con una sola página, que es justo cuando el resumen sí
    importa. Orden de lectura: agregado → detalle → navegación.
  - **`Order.totals_by_status` agrega EN SQL** (`ITEMS_TOTAL_SQL`, la misma
    fórmula de `OrderItem#total`): `Order#total` se calcula en Ruby, así que
    totalizar con él obligaría a cargar cada pedido con sus partidas (300
    pedidos × 45 renglones) en cada apertura. Devuelve siempre los tres
    estatus, con ceros los vacíos, porque las tarjetas serán también el filtro
    de estatus.
  - **`ReportsController#orders_scope` es el ÚNICO lugar que arma el alcance**
    — listado, resumen y conteo del paginador salen de ahí y no pueden
    divergir. El mismo reporte sirve a los dos roles: el capturista ve el
    resumen y el paginador de SUS pedidos; el servidor, de todos.
- **Filtros del reporte — entrega 1 (2026-08-10):** usuario crea, cliente,
  vendedor, fecha crea (rango) y estatus, en `OrdersFilter` (`app/queries/`).
  - **Se aplican SOBRE el scope ya acotado por rol**, así que un capturista no
    puede filtrar hacia pedidos ajenos ni por URL. El combo "Usuario crea"
    solo se le ofrece al servidor: al capturista le mostraría nombres que no
    puede consultar. Ambos casos con test.
  - **El estatus se aplica aparte** (`apply_status`): el resumen se calcula con
    todos los demás filtros pero SIN él, porque sus tarjetas **son** el filtro
    de estatus y deben seguir mostrando el panorama completo para poder saltar
    entre ellas (volver a picar la tarjeta activa lo quita).
  - **Las fechas se interpretan en hora LOCAL**, igual que la columna Fecha del
    reporte (`created_at.localtime`). Con `Time.zone` en UTC, un pedido
    capturado a las 19:00 del día 10 se guarda como 01:00 del 11: filtrar en
    UTC lo dejaría fuera del mismo día que la pantalla le muestra al usuario.
    Test con esa hora exacta.
  - **El formulario no lleva `page`:** cambiar un filtro regresa a la primera
    página; si no, se cae en una página que ya no existe y la tabla sale vacía.
    El `per_page` sí viaja.
  - Los catálogos de una rueda son chicos (3 capturistas, 15 vendedores, 47
    clientes), así que van en combos con filtro de texto — se descartó el
    buscador que se había propuesto para cliente. Solo producto lo necesitará
    (13,222).
  - **Trampa de tests:** el renglón "No hay pedidos capturados" también es un
    `<tr>`; contar `tbody tr` daba 1 con la tabla vacía y escondía un fallo.
    Se descarta por su celda con `colspan`.
- **Filtros del reporte — entrega 2 (2026-08-10):** proveedor, marca y
  producto. No son del pedido sino de sus partidas ("pedidos que traen al menos
  una partida de MAKITA").
  - **Los tres se reducen a un conjunto de productos** (`matching_products`,
    intersección de los tres) y se aplican con `WHERE orders.id IN (SELECT
    order_id FROM order_items WHERE product_id IN …)`. **Nunca con un JOIN a
    `order_items`:** unir repetiría el pedido por cada partida que coincida en
    la tabla e inflaría el importe del resumen, que ya hace su propio join
    para sumar.
  - **Decisión del usuario: con un filtro de partida activo, los importes son
    los de las PARTIDAS QUE COINCIDEN, no los del pedido completo.** Quien
    pregunta "¿cuánto vendió MAKITA?" quiere la venta de MAKITA, no el tamaño
    de los pedidos donde aparece — y con dos proveedores los totales se
    traslaparían. Aplica al resumen, a la columna Total y a Renglones.
  - Como el mismo número pasa a significar otra cosa, **la pantalla lo dice**:
    "Importes de las partidas de MAKITA" arriba del resumen.
  - En el resumen la restricción va como **`CASE` dentro del `SUM`**, no como
    condición del join, para que el conteo de pedidos no cambie. Los importes
    por pedido de la página salen de **una sola consulta agrupada** para los 25
    visibles, no de recalcular pedido por pedido.
  - **Producto es buscador con autocompletado** (no combo: son 13,222).
    Sugiere conforme se teclea (`GET /reports/product-options`, reusando el
    controller `autocomplete` del paso 2) y al elegir una opción escribe su
    **código** en el campo y filtra — el código va a 6 dígitos, así que como
    texto de búsqueda identifica a ese producto y a ningún otro. Se conserva el
    texto libre: "disco flap" acota a esa familia entera, que un selector de un
    solo SKU no podría. Las sugerencias se acotan al universo de quien mira.
    (Primero se hizo solo como campo de texto; el usuario pidió ver y elegir
    coincidencias.)
  - El aviso enuncia distinto el producto: "Importes de las partidas de MAKITA"
    (proveedor/marca) vs "…que coinciden con \"037857\"" — un código suelto
    tras "de" se lee como si fuera un proveedor.
  - Proveedor y marca se ofrecen del **universo de quien mira**
    (`available_suppliers`/`available_brands`): al capturista no se le muestran
    opciones que jamás podrían aparecer en sus pedidos. El índice de
    `products.brand_id` ya existía.
  - **Trampa de tests:** los folios locales con `rand` chocaban contra el
    índice único de `local_folio` y el test fallaba de forma intermitente —
    secuencia correlativa.
  - **Estética, en tres pasadas con el usuario (mismo día):**
    1. Filtros y tarjetas se habían hecho con paneles translúcidos
       `bg-white/5`, que sobre el shell negro con patrón se lavan ("no se
       aprecian bien"). Norma en `docs/convenciones-visuales.md`.
    2. Se retomó la card del levantamiento de pedido: marco dorado con **sus
       mismos márgenes** (`p-6 sm:p-8`) y los controles directamente sobre el
       dorado, **todos del mismo fondo** (pill negro) — antes unos eran negros
       (combos) y otros blancos (campos de escritura), y se veía disparejo.
       Las tarjetas de estatus quedaron crema con su badge de color y la de
       Total en **coral**, igual que el renglón Total de la card de totales.
    3. **Compactada:** fuera el título "Filtros" y fuera las etiquetas arriba
       de cada campo — el nombre de la dimensión va DENTRO del control como
       hint ("Todos los proveedores"), que es la línea que se ahorra por
       filtro. Y **filtra al seleccionar** (`change->form-submit#submit`), así
       que desapareció el botón "Filtrar"; solo queda "Limpiar filtros", con
       `justify-self-start` para que la celda del grid no lo estire y una
       acción secundaria no pese más que los filtros.
  - Los tres filtros de partida van juntos en el orden: mezclados con los del
    pedido confundían qué acota qué.
  - **Selector de rango de fechas hecho a mano** (`date_range_controller` +
    `shared/_date_range`): un solo control con calendario de un mes, rango por
    **arrastre** (escritorio) o **clic-clic** (tablet, donde arrastrar es
    incómodo). Se descartó vendorear Flatpickr: el proyecto no tiene ninguna
    dependencia de JS externa (combo, autocompletado y modal están hechos a
    mano) y su CSS habría que sobrescribirlo casi por completo.
    - Al completar el rango escribe los hidden y **dispara `change` en el
      `from`**, que es lo que hace que el formulario filtre solo. El partial
      recibe `input_data` para esa acción: sin eso el evento burbujea al form
      pero nadie lo escucha (los controles llevan la acción uno por uno, y no
      el form completo, para que el campo de filtrar opciones del combo no
      dispare envíos de más).
    - **Trampa del preview:** el día bajo el cursor no se marcaba durante el
      arrastre — `end` sigue nulo, así que no era "extremo" ni caía "dentro"
      del rango. Hay que tratar `hover` como extremo mientras `dragging`.
    - **Trampa grande (la reportó el usuario: "sigue sin seleccionar la
      segunda fecha"):** el grid se reconstruía en cada movimiento y en cada
      selección. Eso destruye el botón que está bajo el cursor, y como
      **Stimulus enlaza las acciones de los nodos nuevos de forma asíncrona**
      (MutationObserver), el clic siguiente caía en un botón todavía sin
      acción y el segundo día no se registraba — intermitente y **invisible
      con eventos sintéticos**: solo apareció al probar con clics reales del
      mouse. Fix: el grid se **construye** solo al abrir o cambiar de mes
      (`buildGrid`) y la selección solo **repinta clases** (`paint`). Regla
      general: no reconstruir DOM que está recibiendo eventos de puntero.
    - **Rango de un solo día:** dos clics sobre el mismo día. La etiqueta
      muestra una sola fecha, no "X — X".
    - **Hoy siempre marcado** con anillo coral, aunque no sea parte del rango:
      es la referencia para ubicarse. Y sin rango elegido, el calendario abre
      en el mes actual.
    - Todo en fecha **local**: `new Date("2026-08-10")` se interpreta como UTC
      y en México adelanta un día; se parte el ISO a mano.

### Sistema visual y detalles de pantalla (decisiones)

Las **normas** que salieron de aquí viven en `docs/convenciones-visuales.md`
(shell, roles por color, iconografía, hover, deshabilitado al 60%, pills,
textos al usuario) — se cargan solas. Aquí queda el porqué y lo específico de
cada pantalla.

- **Origen (2026-07-27/28):** el sistema visual se iteró **en vivo con el
  usuario** tras migrar todo al shell oscuro; varias reglas nacieron de que él
  detectara inconsistencias entre pantallas ("no hay consistencia entre
  transparencia y deshabilitado", "en unas cards crece solo el contenido") y
  pidiera homologar en todo el proyecto. Por eso las convenciones se escriben
  como norma global, no como el arreglo de una pantalla.
- **Paso 2 enmarcado** como los pasos 1 y 3: card dorada de marco delgado
  (`p-2`, separaciones internas del mismo grueso), barra negra con folio +
  badge a la izquierda y botones a la derecha; observaciones y totales de la
  misma altura ("Guardado ✓" es overlay dentro del textarea). La card del paso
  1 se quedó **dorada** — el usuario revirtió el crema ahí.
- **Pills Proveedor/Marca:** Marca es espejo completo de Proveedor
  (`User#brands_in`, `available_brands`/`current_brand`, `PATCH /active-brand`
  con `ActiveBrandsController` validando pertenencia). Sin proveedores ya no
  sale "Proveedor: —". `_supplier_pill` se eliminó al generalizar. Tests en
  `context_pills_test` (4).
- **Encabezado del pedido:** el tipo (Factura/Remisión) solo ofrece lo que el
  cliente tiene en el ERP — sin perfiles fiscales no hay Factura; sin
  remisiones no hay Remisión; con uno solo, tipo fijo sin radio; sin ninguno,
  aviso y no se captura. WhatsApp se eliminó por completo del resumen (vista,
  ruta, acción y asset).
- **Paso 2 — contenido (2026-07-30):** la columna Total de la tabla incluye
  descuento e IVA (`item.total`, como el PDF; antes era cantidad × precio y no
  cuadraba con el Total del pie). La card del encabezado usa los **mismos
  labels** que los combos del paso 1 (RFC — razón social, código —
  descripción del CFDI, sucursal — dirección completa). El buscador de
  producto recibe el foco al entrar. El hub de reportes ganó "← Volver al
  menú" (título arriba de las cards a la izquierda, botón a la derecha).
- **Observaciones siempre en mayúsculas (2026-07-30):** `normalizes` en `Order`
  es la fuente de verdad (el texto viaja al ERP, que maneja mayúsculas) y la
  clase `uppercase` del textarea es solo presentación; el placeholder va
  exento. Lo ya guardado conserva su caja hasta que se edite.
- **Cambiar razón social actualiza el Uso de CFDI (2026-07-30):** controller
  `cfdi-default` con el mapa perfil → uso default del ERP; el `change` del
  combo de razón social clickea la opción del combo de CFDI (reutiliza la
  lógica del select). Sin default configurado, no toca la selección.
- **Reporte de pedidos capturados:** Fecha · Hora (local, separadas) · Cliente
  (clave — nombre) · Vendedor (id — nombre) · Clave local (enlace al pedido) ·
  Renglones · Total · Estatus. El servidor ve además Capturista al inicio.

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
- **Bug "no se reflejan en el ERP" (2026-07-30):** comparando nuestros pedidos
  transmitidos (1A0016–1A0020) contra pedidos CAPTUR normales del ERP, columna
  por columna y midiendo invariantes sobre 1.2M de pedidos históricos, nos
  faltaban: **`renglones`** (SIEMPRE = # partidas; nosotros dejábamos 0 — la
  causa más probable), **`id_sucursal_crea=1`**, **`hora_crea` sin
  microsegundos** (los únicos 5 pedidos del histórico con micros eran los
  nuestros; `Sequel::CURRENT_TIME` los incluye → `localtime(0)`) y
  **`observaciones=' '`** cuando viene vacía (moda del ERP). `hora_transmision`
  SÍ lleva micros en el propio ERP — se queda. NO era problema:
  `flujo_recorrido=f` (lo prende un proceso posterior del ERP; pedidos ajenos
  recién capturados también lo traen en `f`) y los campos operativos del
  detalle en 0 vs NULL (el histórico trae ambos). Corregido en
  `OrderCreate.insert_header/insert_details` + UPDATE de remediación a los 5
  pedidos ya transmitidos. Método: **la fila del ERP es la especificación** —
  ante dudas, medir la invariante en el histórico con COUNT.

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
- **Corridas huérfanas (2026-07-28):** un `SyncRun` nace `running` y solo el job
  lo cierra; si el proceso muere a media corrida (apagón, cierre de `bin/dev` —
  con el adapter de jobs en proceso el job no sobrevive), el renglón queda
  `running` para siempre: el panel gira "en progreso" eterno y la guarda bloquea
  nuevas corridas. Le pasó al usuario en la laptop y ni el reinicio lo curaba.
  Fix: `SyncRun.recover_orphaned!` desde
  `config/initializers/sync_run_recovery.rb`, dentro de
  `Rails.application.server { }`. Validado con un server efímero que barrió al
  huérfano sembrado, y el runner que lo sembró no lo tocó. (La norma
  generalizada quedó en `docs/convenciones-codigo.md`.)
- **Con pedidos que solo viven en la laptop no se sincroniza ni se cierra la
  rueda (2026-08-10).** Regla única en `Sync::Guards`, con dos guardas:
  - `no_draft_orders!` (sync-**up**): solo los borradores estorban.
  - `no_local_orders!(error, accion)` (sync-**down** y **cerrar rueda**): las
    dos operaciones borran TODOS los pedidos locales, así que bloquean por
    borradores **y** por finalizados sin transmitir. `accion` completa la
    frase ("al obtener la información" / "al cerrar la rueda") — es lo único
    que cambia entre ambas. Los transmitidos nunca bloquean: ya viven en el
    ERP.
  - **sync-up:** solo toma `captured`, así que el borrador no se transmitiría
    y el operador creería que ya todo llegó al ERP.
  - **sync-down:** su replace hace `Order.destroy_all` — el borrador se
    **borraba en silencio**. Antes NO bloqueaba (decisión original: el
    sync-down es de oficina, antes del evento, con nadie capturando); se
    cambió porque el modelo de operación es laptop-servidor **en el evento**,
    en la misma LAN, y entre días de una rueda el escenario "descargar
    mientras alguien captura" pasó de imposible a plausible. Hubo que
    reescribir el test que fijaba lo contrario.
  - En `Down.guard!` los borradores se revisan **antes** que los capturados
    sin transmitir: son el prerrequisito del prerrequisito (con borradores
    vivos tampoco se puede transmitir, así que avisar primero de los
    pendientes mandaría al operador a un botón que también lo rechazaría).
  - El mensaje completo vive en la guarda (los controladores solo hacen
    `alert: e.message`); antes el controlador le concatenaba la acción.
  - **El sync-down avisa de ambos casos de una vez** ("Hay 2 pedidos en
    borrador y 3 sin transmitir; se perderían al obtener la información. Pide
    que terminen o descarten los borradores, transmite los demás, y vuelve a
    intentar"). El orden de solución está forzado, pero en un evento el
    operador necesita ver el camino completo desde el primer intento para
    organizar a su gente, no descubrirlo de mensaje en mensaje.
- **Lenguaje de los mensajes al usuario (regla del usuario, 2026-08-10): sin
  vocabulario técnico.** Quien los lee está en el evento resolviendo un
  problema, no depurando el sistema. Barrido en los avisos del panel:
  "corrida de sync en curso" → "Se está obteniendo información o transmitiendo
  pedidos"; "el replace purga los pedidos locales" → "se perderían al obtener
  la información"; "Descarga iniciada" → "Obteniendo la información";
  "N pedido(s) locales eliminados" → "Se eliminaron N pedidos de esta laptop".
  Los mensajes **concuerdan en número** (`Guards.pedidos/lo/perderia/
  transmitelo`): un "se perderían 1 pedido" delata descuido justo cuando el
  operador necesita confiar en lo que lee. Los detalles técnicos de fallas de
  API (p.ej. "respuesta sin clave_pedido") se conservan: son diagnóstico, no
  instrucción, y van al panel/log.
- **Detalle de la guarda del sync-up:** tres puntos de llamada: el
  **controlador** (antes de crear el `SyncRun`, para que una condición previa
  no quede registrada como corrida fallida), `run!` (cubre `rake sync:up`, que
  aborta legible) y el **job** (solo por carrera: un borrador creado entre el
  pre-chequeo y el arranque).
  - **Criterio de UI decidido por el usuario:** sigue el patrón de "Cerrar
    rueda" — la card NO se bloquea, el modal de confirmación aparece normal y
    el motivo se avisa en el **toast al confirmar**. (Se propuso bloquear la
    card como hace "Elegir rueda" con rueda en curso; el usuario prefirió el
    aviso.) Nota: hoy el menú mezcla ambos criterios — las condiciones de sync
    (corrida viva) se muestran bloqueando la card, y las de datos (pedidos
    pendientes) solo avisan al confirmar.
  - **Riesgo operativo — ver "Próximos pasos":** con las tres operaciones
    bloqueadas, un borrador abandonado (capturista que se fue, tablet muerta)
    deja la laptop **atorada**: no se transmite, no se obtiene información y
    tampoco se cierra la rueda. El escape hoy es parcial: el reporte "Pedidos
    capturados" muestra `Order.all` para el rol servidor, así que el operador
    ve cuáles están en borrador y de quién son, pero **no puede descartarlos
    él mismo**. El usuario lo dio por dentro del alcance, a resolver después.
  - **Homologado el mismo día:** "Obtener información" tenía el mismo hueco —
    con pedidos capturados sin transmitir creaba el `SyncRun`, el job reventaba
    con `Down::GuardError` y quedaba una **corrida fallida** (y sucia la card
    de "última descarga") por una condición previa que nunca se intentó.
    `Sync::Down#guard!` (privado de instancia, sin estado del objeto) pasó a
    ser `Sync::Down.guard!` de clase y `ServerController#sync_down` lo llama
    antes de crear el run, con `rescue` → toast. El job conserva su rescue como
    red para la carrera. **Los tres botones del panel quedan con el mismo
    trato:** condición no cumplida se avisa al confirmar, sin registrar
    corridas que no ocurrieron.
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

