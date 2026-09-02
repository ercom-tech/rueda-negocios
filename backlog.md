# backlog — rueda-negocios

Funcionalidades y definiciones **pendientes de implementar**. Se atienden con
el flujo PAIVD; al cerrarse, el aprendizaje se registra en `memory.md` y el
renglón se borra de aquí.

Separación: **aquí** va lo que falta hacer; en **`memory.md`**, las reglas y
aprendizajes de lo que ya se hizo.

## Prioridad alta

### Desplegar lo remediado (4ª a 9ª) en la laptop y en la VM de testing

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
- **En la laptop:** `bin/rails db:migrate` (migraciones de pid,
  credit_wholesale_price y las de promociones) + `bin/rails
  tailwindcss:build` (obligatorio: hay clases nuevas en cada lote).
- **Checks post-deploy** (transmitir un pedido de prueba con una partida del
  genérico): `id_rueda ≠ 0`, `nombre_capturado` poblado (≤40), precio de
  partida = `cred_mayoreo_precio`, y los de remisión de siempre
  (`consec_remision ≠ 0`, `rfc = XAXX010101000`, `c_UsoCFDI = S01`,
  `fecha_crea` = captura). **Y uno que faltaba:** transmitir una REMISIÓN con
  monto de división y comprobar `dividir_facturas ≠ 0` — es lo único que
  comprueba la corrección del 2026-08-24 contra el ERP.
- **Imprimir el PDF de un pedido de ~20 partidas** y verificar que trae los
  cuatro totales y el importe en letra en la misma hoja. Es el check de la 8ª
  auditoría: en esa franja el papel salía sin totales y con hojas en blanco.
- **Los pasos, con su comprobación uno por uno, están en
  `docs/despliegue-laptop.md`.** Dos que parecen opcionales y no lo son: sin
  `bundle install` la app NO ARRANCA (Bundler falla antes de Rails y el
  servicio entra en bucle), y sin `systemctl restart` los initializers nuevos
  no existen — el reload de development recarga `app/`, no
  `config/initializers/`.
- **Cambios visibles** que anunciar: coral `#bd5343`, favicon de tuerca,
  rojo de avisos más oscuro, mensajes nuevos del panel y del 422; del lote
  de promociones: la flama de promoción, el coral movido al **Subtotal**, el
  botón que ahora dice **"Guardar"**, el aviso "Se muestran las primeras 50
  coincidencias" en los buscadores, y la línea "Dividir facturas cada" en el
  PDF; y del lote del 2026-09-02: el **reporte de productos** (tercera card
  del hub, con descarga en CSV y Excel), los **encabezados ordenables** del
  reporte de pedidos, la **desaparición del tope de 45 partidas** (el contador
  se queda, ahora informativo y contando también los regalos) y la **tabla de
  partidas invertida** — la más reciente arriba, con el consecutivo contando
  hacia atrás (el PDF y el ERP siguen en 1, 2, 3).
- Candidato aparte: no existe handshake de versión laptop↔API (`/` y
  `/health` no la exponen) — esta clase de desfase seguirá siendo invisible
  hasta que exista.

### Pasar a FECEGO la lista de productos con crédito mayoreo en $0 (antes del 27-ago)

**Son 414, no 102** (7ª auditoría: 302 con precio 0 y 112 sin renglón de precio
vivo; el 102 de la 6ª no se reproduce con ningún recorte). Ninguno está en el
universo de una promoción, así que no afectan descuentos ni regalos.

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
`ApplicationSystemTestCase` (Chrome headless) y cuatro archivos:
`order_items_test.rb` (nació para cazar el modal de quitar partida que se
cerraba solo), `order_header_test.rb` (anillos rojos del paso 1),
`sync_pause_feedback_test.rb` (la pausa durante un sync, 5ª auditoría) y `generic_item_flow_test.rb` (el fuera de catálogo, punta a punta). Se
corren con `bin/rails test:system`, aparte de la suite normal.

**Lo que falta cubrir**, por orden de dolor si se rompe:

- **Calendario de rango** del reporte: arrastre, clic-clic, preview, rango de
  un solo día, día actual. Ahí ya se escapó el segundo día que no se
  registraba. Ojo: los eventos sintéticos NO lo reprodujeron.
- **Encabezados ordenables** del reporte de pedidos (`fd7cb89`): que el clic
  reordene de verdad, que el segundo invierta, y que el orden sobreviva al
  cambiar de página y de filtro. Se verificó con clics reales al construirlo
  —incluida la captura a 768 px— pero no quedó prueba de sistema; la cobertura
  que hay es de integración.
- **Filtros del reporte de productos** (`c61d68d`): los combos disparan
  `form-submit` al cambiar, que es JS. Mismo caso que el anterior.
- **Buscador de producto**: autocompletado, agregar al pedido, contador de
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


### Mostrar el monto de división que el cliente ya tiene configurado (BAJA)

`vta_cliente.dividir_facturas` existe en el ERP (201 de 42,472 clientes) y no
se exporta, así que el combo del paso 1 siempre arranca en 0. De los 112
clientes de la rueda 3, **tres** lo tienen: CONDAV $25,000, MASAAA $5,000,
SARUCA $2,000.

**Lo que NO hay que hacer es precargarlo.** La verificación adversarial de la
8ª auditoría mostró que el ERP tampoco lo prefilla —la coincidencia
cliente↔pedido va de 50.5% a 99.5% *según quién captura*, y sobre el mismo
cliente un capturista coincide 0% y otro 93.8%: se teclea a mano— y que el 0
se elige a propósito el 12% de las veces sobre clientes que sí tienen tope
(1,096 de esos 1,490 pedidos superaban el tope y aun así se capturaron en 0).
Precargarlo rompería paridad con el ERP y con la práctica real.

Lo defendible es **exportarlo y mostrarlo como dato informativo** junto al
combo ("este cliente suele dividir cada $25,000"), dejando la decisión al
capturista. Sin daño observable en 2.5 años: los pedidos del escenario temido
cancelan menos que el promedio (0.56% vs 0.75%) y se pagan al 100%.

### El pid no delata a un job muerto con el adaptador `:async` (BAJA)

`SyncRun` detecta corridas huérfanas por el pid de su dueño, y `SyncUpJob`
registra el suyo real (`run.update!(pid: Process.pid)`) justo para eso. Pero la
laptop del evento corre en **development**, donde ActiveJob usa `:async`: el
job vive en un hilo DENTRO de puma, así que ese pid **es el de puma**. Si un
job muriera de golpe, la corrida quedaría `running` con un dueño perfectamente
vivo, el corte por boot tampoco aplicaría —puma no se reinició— y el panel se
quedaría bloqueado con la captura pausada.

**No es lo que pasó el 2026-08-25** (aquello era el broadcast perdido, ya
resuelto), y por eso el arreglo que se había escrito se revirtió: no había
defecto que curar y el remedio tenía su propio riesgo — un umbral por debajo
del peor caso legítimo mata una corrida que sigue transmitiendo y libera la
guarda encima de ella.

Si algún día aparece un cuelgue de verdad, la forma que ya estaba pensada:
`Sync::Up#run!` acepta un bloque que late al terminar CADA pedido (incluidos
los fallidos, que son los que alargan el lote), y el umbral se mide contra el
techo de UN pedido (`OPEN_TIMEOUT + READ_TIMEOUT`), no contra la duración
total — con el lote más largo posible el hueco entre latidos no crece. El
sync-down no late (descarga acotada + import en una transacción), así que su
techo se mide desde el arranque.

Mitigación que ya existe hoy: el sondeo del panel (`sync_status_controller`)
consulta el estado real cada 3 s, así que un cuelgue se ve como tal en vez de
confundirse con "el mensaje no llegó".

### Montos de división fuera del catálogo (BAJA, asimetría)

El ERP tiene pedidos con montos que no están en `vta_pedido_monto_divide`
(7,000, 20,000, 40,000, 43,500, 160,000, 300,000 — uno cada uno, legacy).
Nuestro `Order#dividir_facturas_in_catalog` los rechazaría, mientras que
`rueda-api/app/queries/order_create.rb` los acepta sin validar contra el
catálogo. No es defecto activo —el combo solo ofrece los del catálogo—, pero
las dos puntas no coinciden en qué consideran válido.

### Productos de promoción que no llegan al catálogo (antes del 27-ago)

El panel avisa **186** al obtener información en testing (eran 119 el 24-ago:
subieron, así que se movió algo en la configuración). Son productos que una
promoción `canal_venta='RUN'` de la rueda incluye, pero cuyo proveedor o marca
no está dado de alta en la rueda — configuración del ERP, no defecto de la app.

La consulta que los lista **con su causa** está en `docs/diagnostico-erp.md`.
Hay que correrla en testing, llevarle el agregado a FECEGO y que decidan por
promoción: dar de alta el proveedor/marca, o desactivar esa promoción para la
rueda. No hay salida general por el lado del capturista: **8,665 de los 9,981
productos en promoción de la rueda 3 tienen el descuento por encima de su
`descto_tope`** (86.8%).

*Medido el 2026-09-02 sobre el ERP de desarrollo: `id_empresa = 1`, promociones
`RUN` vivas de `id_rueda_negocio = 3`, descuento = el del código o el mayor de
sus escalones, tope = `com_producto_has_precio.descto_tope` del renglón vivo de
menor `consecutivo` (el mismo que usa `Export#products`).* La proporción bajó
del 99.93% de agosto —eran 6,042 de 6,046— porque entraron HTOO01 (1,921
productos), PESO10 (1,932) e INO010 (82); **PESO10 va al 9% y 1,305 de los
suyos SÍ caben dentro del tope**, así que "no hay salida" ya no es universal.
Re-medir antes de llevárselo a FECEGO: la cifra se mueve con cada promoción
que se configura.

### Una desconexión del ERP no es un "error interno del servidor" (BAJA)

`rueda-api` mete `Sequel::DatabaseDisconnectError` en el saco genérico del 500,
así que el operador lee *"Error interno del servidor; no se guardó nada"* —que
suena a bug de la app— cuando lo que ocurrió fue que el Postgres del ERP cerró
las conexiones a media transacción (`PQconsumeInput() FATAL: terminating
connection due to administrator command`).

Pasó **dos veces en testing** (25 y 26 de agosto), las dos con el mismo pedido
entrando limpio al reintentar. El comportamiento es correcto —`OrderCreate.call`
envuelve todo en `DB.transaction`, así que no queda nada a medias, y la PK de
negocio evita duplicar si algo hubiera entrado—; lo que está mal es solo el
rótulo, que manda a "revisar el registro del servidor" en vez de decir
"reintenta".

**Arreglo:** un `rescue Sequel::DatabaseDisconnectError` propio en
`app/application.rb`, con **503** y un mensaje del estilo "se perdió la conexión
con la base del ERP; el pedido no se guardó, vuelve a transmitir". Y el texto
correspondiente en `Sync::Up#failure_reason`, que es donde se traduce cada tipo
de falla a lenguaje de operación.

**No se hizo antes del evento a propósito:** obliga a redesplegar `rueda-api`, y
el caso ya se resuelve reintentando. Se pospuso el 2026-08-26, a un día de la
rueda.

**Aparte, para preguntarle al equipo del ERP:** dos reinicios de Postgres en dos
días no parece casualidad. Si hay un trabajo de mantenimiento programado,
conviene saber a qué hora para no transmitir encima.

### Medir la captura con pedidos muy largos (BAJA)

Al quitar el tope de 45 partidas (2026-09-02) un pedido puede tener los
renglones que sea. La tabla de captura repinta **completa** en cada cambio de
cantidad o descuento —15 consultas por repintado tras la optimización de la 5ª
auditoría—, y eso está medido con 45 renglones, no con 150.

Si en la próxima rueda aparecen pedidos muy grandes y el capturista siente
lentitud al teclear cantidades, es el primer lugar donde mirar. La salida
natural sería repintar solo la fila tocada más el bloque de totales, en vez de
la tabla entera.

### Descartar un pedido que el ERP pudo haber recibido (MEDIA)

`Sync::Up` tiene tres rescues que dejan el pedido en `captured` diciéndole al
operador *"pudo haber entrado al ERP: vuelve a transmitir sin editar"* —
`Net::ReadTimeout`, `SystemCallError`/`JSON::ParserError` y
`ActiveRecord::ActiveRecordError` (este último es literal: "el pedido entró al
ERP pero no se pudo guardar su folio en esta laptop").

Pero `captured` es `editable?`, o sea con el botón **Descartar** vivo. Si el
capturista lo usa, el pedido desaparece de la laptop y el ERP lo surte,
embarca y cobra igual: una venta que nadie pidió (9ª auditoría).

Es la **cuarta puerta** del mismo defecto. La 6ª auditoría cerró el caso
`transmitted?`; `3e0139d` cerró el candado de promoción que hacía sobrevivir al
pedido; esta sigue abierta.

**Lo que NO sirve:** avisar en el modal. Un texto informa pero no impide nada —
quien va de prisa confirma igual.

**Forma propuesta:** una columna `erp_maybe_present_at` que esos tres rescues
sellen, y bloquear el descarte mientras esté puesta, igual que con un pedido
transmitido. La salida se enuncia y es la que ya dice el mensaje de falla:
**volver a transmitir**. `OrderCreate` es idempotente, así que si el ERP ya lo
tenía devuelve su folio y el pedido pasa a `transmitted` —y entonces cae en la
regla que ya existe—; y si no lo tenía, entra. En los dos casos la duda
desaparece sola.

**El costo que hay que aceptar antes de hacerlo:** sin red ese pedido no se
puede descartar. Es correcto —sin red tampoco se puede resolver la duda— pero
es una restricción real para el capturista en el salón. Variante si estorba:
bloquear solo al capturista y permitírselo al equipo-servidor, que es quien
puede verificar el ERP; cuesta una regla más en el modelo de permisos.

**Pospuesto el 2026-09-02** (decisión del usuario): es el único punto de la
remediación con migración, y su escenario exige que primero falle la red **y**
que el capturista decida descartar justo ese pedido.

### Dos asperezas visuales del reporte de productos (BAJA)

Salieron de la 9ª auditoría y se dejaron fuera de la remediación a propósito:
arreglarlas bien pide rediseñar, y no estaba claro cuál es la forma correcta.

- **El paginador queda encajado entre las dos tablas.** Su conteo ("2
  productos") cuenta solo el catálogo y se lee pegado al encabezado "Fuera de
  catálogo", que trae filas no contadas. La salida no es obvia: separar con
  aire, mover el conteo arriba de la tabla, o replantear el orden de los dos
  bloques.
- **El blanco de clic de los encabezados ordenables es solo el texto**, no toda
  la celda: el `px-4 py-3` vive en el `<th>` y el `<a>` es `inline-flex`. Pasa
  el criterio de WCAG 2.2 por la excepción de espaciado (los centros quedan a
  ≥32 px en horizontal y ≥44 px del enlace de la primera fila), pero en tablet
  es un blanco chico. Se arregla moviendo el padding al enlace
  (`block w-full px-4 py-3` con `justify-*` según el `align`).

### El reporte de productos no ordena por columna (BAJA)

Sus encabezados tienen el mismo `thead` negro, el mismo `font-semibold` y los
mismos rótulos que los del reporte de pedidos, que desde `fd7cb89` **sí**
ordenan al hacer clic. Nada distingue unos de otros, así que invitan a un clic
que no hace nada (9ª auditoría).

Dos salidas, y la primera es la buena si alguien lo pide: **darle orden por
columna**, que además es barato — `catalog_rows` ya se ordena en Ruby, así que
no hace falta tocar SQL ni paginar distinto. La otra es distinguirlos
visualmente de los que sí ordenan, pero eso deja la pregunta viva ("¿por qué
este no?").

Hoy sale ordenado por cantidad descendente, que es como se lee este reporte, y
nadie ha pedido otra cosa.

### El reporte de productos solo ve lo que queda en la laptop (MEDIA)

`ProductSales` suma sobre `accessible_orders`, o sea sobre los pedidos que
**hoy** están en la laptop. Pero el replace del sync-down ejecuta
`Order.purge_transmitted!` en cada obtención de información, así que en una
rueda de varios días el reporte solo cubre lo capturado desde la última: se
transmite el día 1, se vuelve a obtener, y el día 2 el reporte muestra solo el
día 2. Tras "Cerrar rueda", cero. El ERP tiene todo (9ª auditoría).

**Mitigado, no resuelto** (2026-09-02): la pantalla declara que cuenta los
pedidos finalizados que están en esta laptop, y avisa con el número cuando el
sync-down se llevó pedidos (`SyncRun.summary["purged_orders"]`, acumulado de la
rueda). El operador ya no puede leer un total parcial creyéndolo completo.

**La solución de fondo es sacar el reporte del ERP** vía `rueda-api`: es el
único lugar que tiene el evento entero. Tiene un costo que hay que pesar antes
—endpoint nuevo, cambio en el contrato entre repos, y **el reporte dejaría de
funcionar sin conexión**, justo al revés de lo que la app promete durante el
evento—, así que quizá lo correcto sea un reporte distinto (de oficina, contra
el ERP) y no mover este. Decidir con FECEGO qué pregunta quieren responder:
"cómo va la rueda ahora" (esta laptop) o "cuánto se vendió en la rueda" (ERP).

Alternativa intermedia sin conexión: guardar un agregado por producto antes de
purgar, dentro de la misma transacción del sync-down.

## Definiciones con FECEGO

### Timbrar una factura con una partida de regalo al 100% (antes del 27-ago)

Las partidas de regalo viajan al ERP con **precio de lista, 100% de descuento
y total $0.00**. Falta la única comprobación que no se puede hacer desde la
base: **que el PAC timbre un CFDI que las contenga.**

Lo que ya está verificado contra el ERP de desarrollo (2026-08-24):

- Existen **612 conceptos de CFDI con `descto_porcentaje = 100`**, y **605 en
  facturas con `pac_ok = true` y UUID del SAT** (597 vigentes + 8 canceladas
  después, por otra razón). Con precios reales: **4 conceptos de $235.95 y 14
  de $277.83**, todos timbrados y sellados.
- Su tasa de fallo es **0.82%** (5 de 609 conceptos al 100% dentro de
  comprobantes tipo I), contra **13.91%** de todos los conceptos de facturas
  del ERP: los conceptos al 100% timbran MEJOR que el promedio.
  *(La versión anterior comparaba 1.14% por concepto contra 19.84% por
  comprobante, y ese 19.84% incluía notas de crédito y pagos —1.23M de filas
  que casi nunca fallan—. Facturas de verdad fallan 37.73%. Corregido en la
  8ª auditoría: mismas unidades a los dos lados, y la conclusión se refuerza.)*
- Un concepto en cero dentro de un CFDI timbrado es rutina aquí: **5.05M
  conceptos con total $0.00 en 466,373 CFDI timbrados** (con `pac_ok` y UUID;
  sin filtrar por timbrado son 5.36M en 467,095).

Lo que NO se pudo cerrar desde la base: de los 7 que no timbraron, dos traen
**CFDI33147 — "El valor del campo ValorUnitario debe ser mayor que cero"**.
Esa regla del SAT habla del *precio unitario*, no del importe, y esos dos
tenían el precio en 0 — un caso distinto al nuestro, que manda el precio de
lista. Pero los otros cinco dicen solo *"Error en la estructura del XML
respecto al ANEXO 20"*: 3 con `pac_error_code = 0` —dos con descripción `?` y
una con el texto del ANEXO 20— y 2 con código 8100. Así que no se puede
afirmar que ninguno venga del importe en cero. Dato que acota el pendiente:
**2 de los 7 no son facturas sino notas de crédito** (tipo E).

**Cómo se cierra:** transmitir a testing un pedido con regalo (receta en la
guía de despliegue: FANDELI, 3 piezas del 027049 = $27,950 → 9% + esmeril
SKIL) y pedirle a FECEGO que lo **facture**. Si el CFDI timbra con `pac_ok =
true`, el tema queda cerrado. Si CFDI33147 aparece, la salida es imitar al ERP
en sus regalos de promoción: dejar el neto en $0.25 + IVA en vez de en cero
(ver `docs/erp-esquema-promociones.md`, sección Regalos) — es un cambio de una
constante en `Promotions::Group`.

Ojo con el orden: esto se valida DESPUÉS de desplegar y transmitir el pedido
de prueba, así que va en el mismo viaje que el paso 4 de la guía.

### Cuántos regalos entrega un escalón con varios (antes del 27-ago)

`vta_promocion_detalle.regalos_permitir` viene en **0** y `regalos_todo` en
**false** en las 38 promociones de la rueda, y FLEXIMATIC (3036) tiene **dos**
productos de regalo en cada uno de sus dos escalones (exhibidores 31245 y
34317).

Lo que dicen los datos del ERP (7ª auditoría), no lo que suponíamos: en los
escalones con regalo configurado solo existen dos combinaciones — `(N≥1,
true)` en 442 y `(0, false)` en 7. **La forma "elige N" no aparece en ninguna
fila**, así que el par nunca se usó para expresar eso. Y de los regalos
efectivamente emitidos en pedidos, el **100%** salió de escalones `(N, true)`:
con `(0, false)` el ERP **nunca ha emitido un regalo**. Los 7 escalones así son
los 4 de esta rueda y 3 de CALIDRA (canal POS).

La pregunta para FECEGO, entonces, no es "¿elige uno o se lleva todos?" sino:
**¿qué significa `(0, false)`, y están bien capturados esos 4 escalones?**
Compararlos con las 442 configuraciones que sí han entregado regalos.

Por ahora la app **entrega todos** los del escalón (decisión del usuario
2026-08-22): es lo que el proveedor prometió, y quedarse corto es peor que
pasarse. Si FECEGO confirma que se elige uno, hay que agregar la elección al
modal de la promoción — hoy no hay pantalla para eso.

Las otras dos promociones con regalo (FANDELI, ITW POLIMEX) traen uno solo,
así que el caso ambiguo es únicamente FLEXIMATIC.


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
