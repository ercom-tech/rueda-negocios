# backlog — rueda-negocios

Funcionalidades y definiciones **pendientes de implementar**. Se atienden con
el flujo PAIVD; al cerrarse, el aprendizaje se registra en `memory.md` y el
renglón se borra de aquí.

Separación: **aquí** va lo que falta hacer; en **`memory.md`**, las reglas y
aprendizajes de lo que ya se hizo.

## Prioridad alta

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

### Pruebas de sistema: el JavaScript no tiene ni una línea cubierta

Detectado en la 3ª auditoría (2026-08-10). No existe `test/system/`, aunque
`capybara` y `selenium-webdriver` ya están en el Gemfile.

**Por qué pesa ahora:** el proyecto acumuló piezas de JS hechas a mano y con
lógica real —calendario de rango (arrastre, clic-clic, preview, fechas
locales), autocompletado, combo custom, paso por múltiplos del empaque con las
flechas, director de foco—, y **todas se validan a mano en el navegador cada
vez**. Ahí ya se escaparon dos defectos que ninguna prueba habría dejado pasar:
el segundo día del rango que no se registraba (DOM reconstruido bajo el cursor)
y una continuación de línea estilo Ruby dentro de JS.

**Alcance:** arrancar con los flujos que más duelen si se rompen —agregar y
quitar partidas, y el rango de fechas del reporte— antes que cobertura amplia.
Ojo: los eventos sintéticos NO reprodujeron el bug del calendario; las pruebas
tienen que ir por clics reales de Capybara.

### `users.prefix` no se lee en ningún lado: decidir si se conserva

El sync-down llena la columna, pero el prefijo del folio lo resuelve
`rueda-api` contra el ERP en vivo (`cnf_persona.prefijo`), así que
`rueda-negocios` nunca la consulta. Decidir: borrarla, o dejarla documentada
como copia de respaldo por si el folio se llegara a armar del lado de la app.

### Pantallas del menú que faltan

- Read-only: productos, clientes, rueda activa.
- Asistencia de clientes.
- Cotización.

### Precios / beneficios especiales de la rueda

Hallazgo ya resuelto: el ERP **no** tiene precios ligados a `id_rueda` — viven
en el catálogo general `com_producto_has_precio` (niveles mayoreo / público /
intermedio / crédito + `factor_descto1..5`).

El "precio especial por rueda" es un **concepto a definir en la app**: modelo
propio con FK `id_rueda` + `id_producto`, o reúso del catálogo. Decisión
diferida.

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

### LAN del evento

IP fija + hostname (mDNS `laptop.local`), router dedicado. Por definir.

## Sync

### Membresías de rueda que el export no trae

`business_round_people` **ya** se sincroniza (2026-07-26, es el universo de
productos por capturista). Siguen sin venir en el export `brands_suppliers` y
`business_round_{brands,suppliers,salespeople}` — el sync-down solo las vacía.
Definir si alguna pantalla llega a necesitarlas.

## Operación y seguridad (fase de strengthening)

### Punto único de falla: la laptop-servidor

Definir backups (`pg_dump` a USB u otro equipo) y evaluar una laptop de
respaldo.

### Endurecimiento del transporte

HTTPS, tokens de autenticación, allowlist, throttling y proxy en AWS para
`rueda-api`. Hoy el transporte es HTTP plano en red interna; la materia prima
para el throttling ya existe (`login_events` registra los intentos fallidos).

### Seguridad de los datos en la laptop

Lleva datos de clientes y precios: cifrado de disco + limpieza post-evento.
