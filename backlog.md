# backlog — rueda-negocios

Funcionalidades y definiciones **pendientes de implementar**. Se atienden con
el flujo PAIVD; al cerrarse, el aprendizaje se registra en `memory.md` y el
renglón se borra de aquí.

Separación: **aquí** va lo que falta hacer; en **`memory.md`**, las reglas y
aprendizajes de lo que ya se hizo.

## Prioridad alta

### 1. El rol servidor debe poder descartar pedidos ajenos

Desde el reporte "Pedidos capturados", donde ya los ve todos con dueño y
estatus.

**Urgente por dependencia:** desde 2026-08-10 las tres operaciones del panel
(obtener información, transmitir pedidos, cerrar rueda) se bloquean si hay
pedidos en borrador. Un borrador abandonado —capturista que se fue, tablet
muerta— deja la laptop **sin salida**. Confirmado dentro del alcance por el
usuario, pospuesto ese día.

**Alcance:** botón + modal de confirmación en el reporte, ruta y guarda de rol.

### 2. Empaquetado / deployment de la laptop-servidor

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

### 3. Instalación de `rueda-api` en la VM de producción

Guía en borrador: `rueda-api/docs/instalacion-vm-produccion.md`. Faltan los
datos reales (hostname, usuario, IP del ERP, puerto final) y ejecutarla.

## Funcionalidad pendiente

### 4. Filtros en el reporte "Pedidos capturados"

Diseño ya acordado (2026-08-10) al construir el resumen por estatus; el
terreno quedó preparado para que sea agregar la barra y los parámetros, no
rehacer.

- **Las tarjetas de estatus SON el filtro de estatus:** se le pica a
  "Borradores · 3 · $12,400" y la tabla se acota, con la tarjeta marcada como
  activa. Evita tener el estatus dos veces (resumen + combo).
- **El resumen refleja todos los filtros menos el de estatus** — las tarjetas
  deben seguir mostrando el panorama completo para poder saltar entre
  estatus. Filtrar por capturista muestra cómo se reparten *sus* pedidos.
- Filtros a agregar en la barra: capturista (**solo para el rol servidor**; el
  capturista ya está acotado a lo suyo), cliente y fecha.
- **Un solo lugar arma el alcance:** `ReportsController#orders_scope` ya es
  ese lugar — listado, resumen y conteo del paginador salen de ahí y no
  pueden divergir.
- **Cambiar un filtro regresa a la página 1** (si no, se cae en una página que
  ya no existe y la tabla sale vacía).
- Los enlaces del paginador **ya** conservan los parámetros de la URL
  (`request.query_parameters.merge`), así que los filtros sobreviven al
  paginar sin tocar nada.
- Layout final: título → filtros → tarjetas de estatus → tabla → paginador.

### 5. Pantallas del menú que faltan

- Read-only: productos, clientes, rueda activa.
- Asistencia de clientes.
- Cotización.

### 6. Precios / beneficios especiales de la rueda

Hallazgo ya resuelto: el ERP **no** tiene precios ligados a `id_rueda` — viven
en el catálogo general `com_producto_has_precio` (niveles mayoreo / público /
intermedio / crédito + `factor_descto1..5`).

El "precio especial por rueda" es un **concepto a definir en la app**: modelo
propio con FK `id_rueda` + `id_producto`, o reúso del catálogo. Decisión
diferida.

### 7. Regalos por promoción

Mencionado por el usuario (2026-08-10) al fijar el tope de 45 partidas: los
regalos pueden hacer que un pedido rebase el tope. Al implementarlos hay que
decidir en `Order#items_count_for_limit` si se excluyen del conteo o si solo
sube `Order::MAX_ITEMS`.

## Definiciones con FECEGO

### 8. Defaults de configuración de la cabecera del pedido

`c_FormaPago`, `c_MetodoPago`, `condicion_pago`, `tipo_precio`,
`id_negociaciontipo`, `id_enviotipo`. Hoy son fijos en
`OrderCreate::HEADER_DEFAULTS` (la moda del ERP). Confirmar cuáles son
correctos para una rueda y si alguno debe salir del cliente en vez de ser fijo.

### 9. LAN del evento

IP fija + hostname (mDNS `laptop.local`), router dedicado. Por definir.

## Sync

### 10. Membresías de rueda que el export no trae

`business_round_people` **ya** se sincroniza (2026-07-26, es el universo de
productos por capturista). Siguen sin venir en el export `brands_suppliers` y
`business_round_{brands,suppliers,salespeople}` — el sync-down solo las vacía.
Definir si alguna pantalla llega a necesitarlas.

## Operación y seguridad (fase de strengthening)

### 11. Punto único de falla: la laptop-servidor

Definir backups (`pg_dump` a USB u otro equipo) y evaluar una laptop de
respaldo.

### 12. Endurecimiento del transporte

HTTPS, tokens de autenticación, allowlist, throttling y proxy en AWS para
`rueda-api`. Hoy el transporte es HTTP plano en red interna; la materia prima
para el throttling ya existe (`login_events` registra los intentos fallidos).

### 13. Seguridad de los datos en la laptop

Lleva datos de clientes y precios: cifrado de disco + limpieza post-evento.
