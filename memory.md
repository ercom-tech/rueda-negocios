# memory — rueda-negocios

Bitácora de decisiones y contexto del proyecto. Se actualiza conforme
avanzamos (paso **Documentar** del flujo PAIVD).

## Estado actual

Estructura de repos definida y ambos con `git init`.
**Descubrimiento del esquema de catálogos del ERP (sync-down) COMPLETADO** y
verificado contra BD viva → `docs/erp-esquema-catalogos.md`. Pendiente aún el
descubrimiento del esquema de **pedidos** (sync-up, alta en ERP).

**Fase A COMPLETADA** (app `rueda-negocios`): `rails new` + modelos del dataset
local, migrado y validado.

**Fase B — arco LOGIN COMPLETADO**: autenticación de capturistas (bcrypt del
ERP) + pantalla de login con el diseño de referencia. La navegación de catálogos
se hará en arcos siguientes, que el usuario irá indicando pantalla por pantalla.

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
  - Contrato compartido (JSON de export + alta de pedidos): fuente canónica
    en `rueda-api/docs/contract.md`, referenciado desde la app.
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

## Riesgos / puntos abiertos

- 🔴 **Entrada de pedidos al ERP:** no existe interfaz previa; hay que crear
  el endpoint en `rueda-api` que inserte en la BD del ERP replicando sus
  reglas. Requiere **descubrimiento del esquema de pedidos del ERP** antes de
  codificar el sync-up. Mayor riesgo.
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

1. **Fase B (resto)** — pantallas de navegación read-only, una por una según
   indique el usuario (productos con marca/proveedor/precio, clientes, rueda
   activa). El login ya está.
2. **Fase C** — API `rueda-api` (Sinatra) + endpoint de export del dataset.
3. **Fase D** — rake sync-down en la app que consume el export y puebla el
   Postgres local (reemplaza el seed dev).
4. Más adelante: descubrir el esquema de **pedidos** del ERP (sync-up / alta) e
   implementar la captura.
