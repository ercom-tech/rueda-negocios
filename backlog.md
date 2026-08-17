# backlog — rueda-negocios

Funcionalidades y definiciones **pendientes de implementar**. Se atienden con
el flujo PAIVD; al cerrarse, el aprendizaje se registra en `memory.md` y el
renglón se borra de aquí.

Separación: **aquí** va lo que falta hacer; en **`memory.md`**, las reglas y
aprendizajes de lo que ya se hizo.

## Prioridad alta

### Desplegar lo remediado (4ª a 6ª) en la laptop y en la VM de testing

**Nada está desplegado desde antes de la 4ª** (la API de testing corre
`b43495a`, del 30-jul: ni siquiera trae el arreglo de remisiones). Con el
lote del 2026-08-17 (precio crédito, id_rueda, genérico 999999) el plan
viejo quedó caduco — verificado en la 6ª auditoría:

- **Prerequisito ERP (antes de todo, en testing 10.1.3.43 y producción):**
  columnas `vta_pedido.id_rueda` (default 0) y
  `vta_pedido_detalle.nombre_capturado` (varchar 40), y el producto 999999
  vivo (`baja=false`). Sin la columna, la API nueva da 500 en TODO pedido.
- **Orden (invertido respecto al plan anterior): ERP migrado → rueda-api →
  laptop.** API nueva + laptop vieja es el único par tolerante (`id_rueda ||
  0`, `nombre_capturado` NULL; el 422 de remisiones es visible y se destraba
  actualizando la laptop). Al revés, la API vieja descarta EN SILENCIO la
  descripción del genérico y la rueda del pedido, y su export deja el
  catálogo local entero sin precio con un sync "exitoso".
- **Ventana: ni transmitir NI obtener información** hasta que ambos lados
  estén parejos. Tras actualizar la laptop, re-correr sync-down contra la
  API nueva antes de capturar.
- **En la laptop:** `bin/rails db:migrate` (dos migraciones nuevas: pid y
  credit_wholesale_price) + `bin/rails tailwindcss:build`.
- **Checks post-deploy** (transmitir un pedido de prueba con una partida del
  genérico): `id_rueda ≠ 0`, `nombre_capturado` poblado (≤40), precio de
  partida = `cred_mayoreo_precio`, y los de remisión de siempre
  (`consec_remision ≠ 0`, `rfc = XAXX010101000`, `c_UsoCFDI = S01`,
  `fecha_crea` = captura).
- **Cambios visibles** que anunciar: coral `#bd5343`, favicon de tuerca,
  rojo de avisos más oscuro, mensajes nuevos del panel y del 422.
- Candidato aparte: no existe handshake de versión laptop↔API (`/` y
  `/health` no la exponen) — esta clase de desfase seguirá siendo invisible
  hasta que exista.

### Pasar a FECEGO la lista de productos con crédito mayoreo en $0 (antes del 27-ago)

102 productos de la rueda 3 quedarán invendibles en la app (crédito $0); 25
tienen ventas vivas 2025-26 (684 partidas, vendidas debajo del público — el
$0 es omisión de captura del catálogo). El top-10 está en el reporte de la
6ª auditoría; re-medir contra el ERP de producción antes de actuar.

### El rol servidor debe poder descartar pedidos ajenos

Desde el reporte "Pedidos capturados", donde ya los ve todos con dueño y
estatus.

**Urgente por dependencia:** desde 2026-08-10 las tres operaciones del panel
(obtener información, transmitir pedidos, cerrar rueda) se bloquean si hay
pedidos en borrador. Un borrador abandonado —capturista que se fue, tablet
muerta— deja la laptop **sin salida**. Confirmado dentro del alcance por el
usuario, pospuesto ese día.

**Alcance:** botón + modal de confirmación en el reporte, ruta y guarda de rol.

### Empaquetado / deployment de la laptop-servidor

Cómo instalar la app en el equipo del evento y servirla en la LAN.

- **Ya existe en el repo:** `Dockerfile` (producción), `bin/docker-entrypoint`,
  `.dockerignore`, `config/deploy.yml` (Kamal) y
  `docs/instalacion-laptop.md` (modo development). Falta el modo empacado.
- **Decisión pendiente:** plataforma (Linux preferido, encaja con la infra de
  FECEGO) y método:
  - **Docker Compose** + `restart: unless-stopped` → reproducible, portable,
    auto-arranque al boot. Recomendado. Falta el `docker-compose.yml`
    (app + Postgres).
  - **Nativo + systemd** (Ruby por rbenv + Postgres del sistema, Puma con
    `SOLID_QUEUE_IN_PUMA`) → más ligero, menos portable entre distros. Hay
    receta de servicio systemd probada en la VM de testing de `rueda-api`.
  - Windows solo como plan B (Docker Desktop con WSL2, con fricción). Ruby y
    Postgres nativos en Windows: frágil, desaconsejado.
- **A resolver al empacar:** `RAILS_ENV=production` (SECRET_KEY_BASE / master
  key, assets precompilados, `config.hosts` para la IP de la LAN);
  persistencia (volumen de Postgres + `pg_dump` a USB); **operación offline**
  (pre-descargar las imágenes Docker en la oficina); primer arranque
  (`db:prepare` + seed del server + `sync:down`).

### Instalación de `rueda-api` en la VM de producción

Guía en borrador: `rueda-api/docs/instalacion-vm-produccion.md`. Faltan los
datos reales (hostname, usuario, IP del ERP, puerto final) y ejecutarla.

## Funcionalidad pendiente

### Pruebas de sistema: ampliar la cobertura del JavaScript

**Arranque hecho (2026-08-11):** existe `test/system/` con
`ApplicationSystemTestCase` (Chrome headless) y tres archivos:
`order_items_test.rb` (nació para cazar el modal de quitar partida que se
cerraba solo), `order_header_test.rb` (anillos rojos del paso 1) y
`sync_pause_feedback_test.rb` (la pausa durante un sync, 5ª auditoría). Se
corren con `bin/rails test:system`, aparte de la suite normal.

**Lo que falta cubrir**, por orden de dolor si se rompe:

- **Calendario de rango** del reporte: arrastre, clic-clic, preview, rango de
  un solo día, día actual. Ahí ya se escapó el segundo día que no se
  registraba. Ojo: los eventos sintéticos NO lo reprodujeron.
- **Buscador de producto**: autocompletado, agregar al pedido, tope de 45
  partidas, aviso de capturista sin proveedor ni marca.
- **Paso por múltiplos del empaque** con las flechas ↑/↓ (`step="any"` y el
  paso implementado a mano) y el auto-guardado en `blur` solo si cambió.
- **Combo custom** (`shared/_custom_select`) y los pills de contexto.
- **Paso 1**: cambio de tipo factura/remisión y los campos que se ocultan.

### Unificar el estilo de las URLs (kebab-case vs snake_case)

El mismo concepto existe con guion y con guion bajo
(`reports/product-options` vs `/orders/:id/product_options`; el scope server
usa kebab). Es pura estética pero toca rutas, vistas y JS: se difirió en la
remediación de la 5ª auditoría para no arriesgar un renombre masivo por un
detalle cosmético. Al unificar, elegir kebab (el estilo del scope server) y
revisar el diff palabra por palabra.

### `users.prefix` no se lee en ningún lado: decidir si se conserva

El sync-down llena la columna, pero el prefijo del folio lo resuelve
`rueda-api` contra el ERP en vivo (`cnf_persona.prefijo`), así que
`rueda-negocios` nunca la consulta. Decidir: borrarla, o dejarla documentada
como copia de respaldo por si el folio se llegara a armar del lado de la app.

### Pantallas del menú que faltan

- Read-only: productos, clientes, rueda activa.
- Asistencia de clientes.
- Cotización.

### Regalos por promoción

Mencionado por el usuario (2026-08-10) al fijar el tope de 45 partidas: los
regalos pueden hacer que un pedido rebase el tope. Al implementarlos hay que
decidir en `Order#items_count_for_limit` si se excluyen del conteo o si solo
sube `Order::MAX_ITEMS`.

## Definiciones con FECEGO

### Defaults de configuración de la cabecera del pedido

`c_FormaPago`, `c_MetodoPago`, `condicion_pago`, `tipo_precio`,
`id_negociaciontipo`, `id_enviotipo`. Hoy son fijos en
`OrderCreate::HEADER_DEFAULTS` (la moda del ERP). Confirmar cuáles son
correctos para una rueda y si alguno debe salir del cliente en vez de ser fijo.
`tipo_precio = 'MA'` ya quedó consistente con la decisión de precio (la rueda
vende a crédito mayoreo, la modalidad a crédito del mayoreo — 2026-08-17);
faltan los demás.

### LAN del evento

IP fija + hostname (mDNS `laptop.local`), router dedicado. Por definir.

## Sync

### Membresías de rueda que el export no trae

`business_round_people` **ya** se sincroniza (2026-07-26, es el universo de
productos por capturista). Siguen sin venir en el export `brands_suppliers`,
`business_round_{brands,suppliers,salespeople}` y **`business_round_clients`**
— el sync-down solo las vacía. Definir si alguna pantalla llega a necesitarlas.

Ojo con `business_round_clients`: tiene asociaciones vivas
(`BusinessRound#clients`, `Client#business_rounds`), así que al construir la
pantalla de **asistencia de clientes** es fácil usarlas dando por hecho que
traen datos — y saldrían vacías en el evento, con el diagnóstico perdido
buscando en el ERP.

## Operación y seguridad (fase de strengthening)

### Punto único de falla: la laptop-servidor

Definir backups (`pg_dump` a USB u otro equipo) y evaluar una laptop de
respaldo.

### Endurecimiento del transporte

HTTPS, tokens de autenticación, allowlist, throttling y proxy en AWS para
`rueda-api`. Hoy el transporte es HTTP plano en red interna; la materia prima
para el throttling ya existe (`login_events` registra los intentos fallidos).

### Endurecimiento de `rueda-api` contra payloads forjados (5ª auditoría)

La laptop hace imposibles estos casos con sus validaciones de modelo; quedan
abiertos solo para requests directos a la API:

- **Facturas sin validar `rfc`/`c_UsoCFDI`:** un payload forjado con
  `remision=false` y sin rfc insertaría `rfc NULL` — forma que no existe en
  ninguna factura nativa (0 de ~74k). El espejo de lo que ya se hace con
  `consec_remision`: rfc presente y en `vta_cliente_has_fiscales` del cliente,
  `c_UsoCFDI` vigente en `sat_uso_cfdi`.
- **Nota `sucursal=0`:** no existe en nativos (0 de ~110k). Hay 321 clientes
  vivos sin ninguna sucursal viva; si uno entrara a una rueda insertaríamos esa
  forma inédita. Validar duro sería peor (atoraría pedidos legítimos capturados
  antes de una baja — los 72 nativos con sucursal dada de baja se entregaron
  todos); decidir con FECEGO qué significa ese caso.

### Content-Security-Policy en `rueda-negocios`

`config/initializers/content_security_policy.rb` está vacío. No hay ningún
vector XSS activo (4ª y 5ª auditorías); es defensa en profundidad: una CSP
mínima (`default-src 'self'`) al entrar a strengthening.

### Seguridad de los datos en la laptop

Lleva datos de clientes y precios: cifrado de disco + limpieza post-evento.
