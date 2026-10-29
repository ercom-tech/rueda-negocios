# Actualizar la laptop del evento

Cómo llevar a la laptop-servidor una versión nueva. Para instalarla desde cero,
ver `docs/instalacion-laptop.md`.

> **Esta guía vive en el repo a propósito.** Antes era un archivo suelto en el
> directorio temporal de la sesión, y se perdió: cuando hizo falta desplegar no
> había contra qué comparar y el procedimiento quedó en la memoria de nadie
> (9ª auditoría). Si cambia el procedimiento, se cambia aquí.

## Lo que hay que saber antes de tocar nada

**Primero el ERP, siempre.** Hay columnas que el ERP debe tener antes de que la
API nueva pueda escribir: están en `rueda-api/db/erp-prerequisitos.sql`, se
aplican en testing y en producción, y sin ellas la API responde 500 en toda
transmisión (o al listar las ruedas, si falta `prefijo`). El orden completo es
**ERP → rueda-api → laptop**, y las dos últimas se actualizan siempre juntas.
Para saber si el ERP ya está listo, sin adivinar:

```bash
curl -s http://localhost:7011/health    # en el servidor de la API
```

`schema: "ok"` significa que están las columnas, las dos tablas de la
evidencia (`vta_pedido_rueda` y su detalle) y los permisos del usuario de la
API: escritura en las cuatro tablas que transmite y lectura en las que lee el
export (`db/erp-prerequisitos.sql` los da). Si falta algo, responde 503 y lo
nombra; una tabla que falta entera se nombra como tabla. Sin las tablas de la
evidencia **toda transmisión falla**: la evidencia se escribe en la misma
transacción que el pedido. Cómo se aplica el archivo —sin transacción, con
`ON_ERROR_STOP`, y qué comprobar al final— está en las guías de instalación de
`rueda-api` (`docs/instalacion-vm-*.md`, sección de actualizar).

**Y el prefijo de la rueda, capturado en el ERP.** Las columnas no bastan: una
rueda sin prefijo opera, pero sus pedidos salen como `RN-000123` y en el ERP no
se sabe de qué rueda vinieron. El panel lo avisa después de obtener la
información; mejor no llegar ahí. El `UPDATE` y la comprobación de que no se
repita van al final de `erp-prerequisitos.sql`.

**La laptop corre en `development`.** El `ExecStart` es `rails server` pelón,
sin `RAILS_ENV` y sin `Environment=` en el unit. Por eso **todos los comandos de
abajo van SIN `RAILS_ENV`**: con `production` Rails apunta a
`rueda_negocios_production` —otra base, vacía— y además pide `secret_key_base`.

| | |
|---|---|
| Ruta | `~/Proyectos/fecego-rueda-negocios` |
| Servicio | `fecego-rueda-negocios` |
| Puerto | 3000 (`0.0.0.0`, para la LAN del salón) |

**Tres pasos que parecen opcionales y no lo son** (medidos en la 9ª y la 13ª
auditorías):

- **Sin `bundle install`, la app NO ARRANCA.** No es una pantalla rota: Bundler
  falla en `Bundler.setup`, antes de cargar Rails, y con `Restart=always` el
  servicio entra en bucle. En las tablets se ve "No se puede acceder a este
  sitio" y nada en la app dice por qué — hay que ir a `journalctl`.
- **Sin `systemctl restart`, las gemas nuevas tampoco.** Bundler las carga al
  arrancar: el servidor viejo sigue vivo con el código nuevo pero sin la gema.
  Con `roo` (2026-10-08), "Cambiar precios" da pantalla de error con un .xlsx
  (`NameError` de `Roo`) mientras un .csv funciona —Ruby lo lee sin roo—: si
  se prueba solo con CSV, el despliegue parece bueno y no lo está.
- **Sin `systemctl restart`, los initializers nuevos no existen.** El reload de
  development recarga `app/`, pero **no** `config/initializers/`. Un MIME sin
  registrar hace que la pantalla que lo usa dé 500 — y como todo lo demás sí
  tomó el código nuevo, parece que el despliegue salió bien y que la pantalla
  nueva nació rota.

**Hazlo desde la oficina, con internet, y con la rueda cerrada** (el paso 2
lo comprueba). El peor orden posible es `git pull` en el salón sin conexión:
el pull funciona y el `bundle install` falla por DNS. Y **si el lote trae
migraciones, el sitio cae en el momento del pull**, no en el siguiente
reinicio: en development el proceso que sigue vivo recarga `app/` y revisa en
cada petición si hay migraciones pendientes (`migration_error = :page_load`),
así que todas las tablets ven "Algo falló de este lado" hasta que corra
`db:migrate` — que necesita a Bundler (reproducido en la 17ª auditoría). La
única salida en el salón es `git checkout <sha del paso 1>`, sin reiniciar.
Desde la oficina pasa igual entre los pasos 4 y 6, pero ahí no hay nadie
capturando.

## Los pasos

```bash
cd ~/Proyectos/fecego-rueda-negocios
```

| # | Paso | Qué comprobar después |
|---|---|---|
| 0 | **La API ya está actualizada** (ver "La API es aparte", al final): en la VM, `git log --oneline -1` | El sha que se quería, y `curl -s http://localhost:7011/health` → `"schema":"ok"`. Con la API vieja todo lo de abajo "sale bien" —el sync-down baja los precios vacíos sin error— y no se nota hasta capturar (16ª auditoría) |
| 1 | `git status --short` y `git rev-parse --short HEAD` | Vacío. Si sale `Gemfile.lock` modificado (bundler reescribe `BUNDLED WITH`), `git checkout Gemfile.lock` antes de seguir. **Anota el sha**: es el de partida, y de él depende cómo se revierte ("Si algo sale mal"). Sin anotarlo, después del pull ya no hay de dónde sacarlo con certeza (17ª auditoría) |
| 2 | `bin/rails runner 'puts SyncRun.running.count'` y `bin/rails runner 'puts [BusinessRound.active.count, Order.count].inspect'` | `0`, y `[0, 0]`: ninguna corrida viva, y la rueda cerrada (sin rueda activa ni pedidos en la laptop). Si hay corrida, esperar: reiniciar a media corrida la mata (los jobs viven en hilos de puma). Si quedan pedidos, la rueda no se cerró: desplegar así mete en el respaldo del paso 3 trabajo que una reversión puede perder |
| 3 | Respaldo de la BD (comandos en `docs/instalacion-laptop.md`, "Respaldo de la BD de la app") | `pg_restore -l "$DUMP"` lista tablas. **Anota la ruta de `$DUMP`**: "Regresar al respaldo" la necesita y puede correr en otra terminal, horas después. Es la única vuelta atrás del paso 6: `git checkout` no deshace una migración |
| 4 | `git pull origin master` | `git log --oneline -1` coincide con la versión que se quería |
| 5 | `bundle install` | `bundle check` → `The Gemfile's dependencies are satisfied` |
| 6 | `bin/rails db:migrate` | Sin error. Es inofensivo aunque no haya migraciones. Y `bin/rails db:migrate:status \| grep -c "^\s*down"` → `0`: ninguna quedó pendiente |
| 7 | `bin/rails tailwindcss:build` | Termina con `Done in …`. El CSS compilado **no** viaja en el repo (`app/assets/builds/` está en `.gitignore`), así que sin este paso las clases nuevas no existen. Para comprobar que una clase concreta entró, busca su **declaración** y no su nombre: en el archivo las clases van escapadas (`.min-w-\[18rem\]`) y un `grep` del nombre tal cual devuelve 0 aunque esté — p. ej. `grep -c 'min-width:18rem'` → `1` |
| 8 | `sudo systemctl restart fecego-rueda-negocios` | `systemctl status fecego-rueda-negocios` → `active (running)`, sin reinicios acumulándose |
| 9 | Abrir la app en el navegador | Entra al menú, sin error |

## Comprobación después de desplegar

Lo mínimo, en el navegador de la laptop, **en este orden**. El despliegue se
hizo con la rueda cerrada, y sin rueda ningún capturista puede entrar; y desde
el lote del 2026-10-28 el equipo-servidor ya no captura (16ª auditoría). Cada
renglón dice con qué usuario va:

1. **Servidor → Elegir rueda** (la del próximo evento) **→ Obtener
   información**: termina en "✓ Listo" y el panel se destraba **solo**, sin
   recargar (el estado se consulta cada 3 s). Las columnas de **caja** del
   Cotizador dependen de este paso con la API nueva.
2. **Servidor → Cambiar precios**: subir un **.xlsx** con el layout (primera
   fila CODIGO y PRECIO LISTA S/IVA; el de FECEGO es "Cambio precio de lista
   Stihl.xlsx") —un .xlsx y no un .csv: el CSV no usa la gema nueva y no
   comprueba el reinicio—, revisar y aplicar. Anota un código del archivo.
3. **Capturista** (uno de la rueda: que entre él, o pídele su usuario) **→
   Registrar pedido**: elegir un cliente, agregar el producto anotado; nace con
   el precio del archivo y el contador del buscador sube.
4. **Mismo capturista → Cotizador**: sobre una partida de un producto en
   promoción, el modal lista los escalones con el precio por pieza (fuera de la
   vigencia dice que el producto no está en ninguna).
5. **Mismo capturista → Generar cotización → Cliente genérico**: agregar una
   partida y "Guardar"; da un folio que termina en `COT-` y seis dígitos (con
   el prefijo de la rueda delante si lo tiene; el número no vuelve a 1, así
   que no tiene que ser `000001`) y el resumen sin PDF. En **Reportes →
   Cotizaciones capturadas** aparece como "Guardada".
6. **Descartar lo de prueba, las dos cosas**: el pedido del paso 3 (Descartar,
   desde su captura) y la cotización del 5. **El pedido no se guarda ni se
   transmite**: un borrador bloquea el siguiente "Obtener información", y su
   aviso ofrece "guárdalo y transmítelo" — seguido al pie de la letra, el
   pedido de prueba llegaría al ERP como **venta real**.
7. **Servidor → Cambiar precios → Quitar precios cargados**, y **Reportes**:
   las tarjetas habilitadas abren sin error.

- Si el lote trae cambios en el PDF, **imprimir un pedido de ~20 partidas** y
  verificar que los cuatro totales y el importe en letra caen en la misma hoja.

Y contra el ERP, si se transmitió algo:

**Un pedido de la rueda puede ser VARIOS pedidos del ERP** (las partidas de
catálogo se cortan cada 45 y los productos nuevos van aparte), así que la
consulta va por la clave de la rueda —la que reúne las partes—, no por un
folio:

```sql
SELECT ped.clave_pedido, ped.hora_pedido, ped.renglones, ped.total,
       det.consecutivo, det.id_producto, det.id_promocion, det.promo_porcentaje,
       det.descto_porcentaje, det.consec_origen_promo, det.total
FROM fecego.vta_pedido ped
JOIN fecego.vta_pedido_detalle det
  ON  det.id_empresa    = ped.id_empresa
  AND det.clave_cliente = ped.clave_cliente
  AND det.fecha_pedido  = ped.fecha_pedido
  AND det.hora_pedido   = ped.hora_pedido
WHERE ped.id_empresa = 1 AND ped.clave_rueda = '<la clave que muestra la laptop>'
ORDER BY ped.hora_pedido, det.consecutivo;
```

Qué debe verse:

- **Un `clave_pedido` por parte**, con horas distintas (una por parte, no
  necesariamente consecutivas: si el cliente ya tenía un pedido en ese segundo,
  la parte salta al siguiente libre) y la **misma `clave_rueda`**.
- **Cada parte reinicia sus consecutivos en 1**, en el orden en que se
  capturaron (la pantalla los muestra al revés a propósito; el ERP no).
- Las partidas del **999999** están todas en la última parte.
- Una partida de regalo lleva `promo_porcentaje = 100`, `total = 0.00` y
  `consec_origen_promo` apuntando a la partida que la detonó **dentro de su
  misma parte**.
- El detalle del pedido en la laptop lista esos mismos folios.

**Y su evidencia** (`vta_pedido_rueda`): sin ella, el despliegue quedó a medias
— faltan las tablas o sus permisos, y toda transmisión habría fallado:

```sql
SELECT ev.clave_rueda, ev.claves_pedido, ev.capturista_usuario, ev.partidas, ev.total,
       det.consecutivo, det.descripcion, det.id_proveedor, det.id_marca, det.regalo
FROM fecego.vta_pedido_rueda ev
JOIN fecego.vta_pedido_rueda_detalle det USING (id_empresa, id_rueda, clave_rueda)
WHERE ev.id_empresa = 1 AND ev.clave_rueda = '<la clave que muestra la laptop>'
ORDER BY det.consecutivo;
```

Un renglón por partida, con los folios de las partes en `claves_pedido`, el
capturista, y en las partidas del 999999 el proveedor o la marca que se eligió.

## Si algo sale mal

**Primero: ¿a qué sha se regresa?** Al anotado en el paso 1. De eso depende
TODO lo demás (16ª auditoría), y se decide con git, no de memoria:

```bash
git merge-base --is-ancestor 2bcc943 <sha del paso 1> && echo "ya tiene promociones"
git merge-base --is-ancestor 9c53e2e <sha del paso 1> && echo "ya tiene cotizaciones"
```

Esta guía decía "la laptop corre `e990d81`" y no era cierto: el 25-ago ya
tenía promociones, y `e990d81` es anterior a ellas. Seguido al pie de la
letra, restauraba un respaldo con las tablas de promociones bajo un código
que no las conoce (17ª auditoría). Al 2026-10-29 la laptop corre `c63a18a`:
tiene promociones y no cotizaciones, el segundo caso.

- **Anterior a las promociones (`2bcc943`, 2026-08-22).** Ahí el `checkout`
  solo NO basta: el código viejo
  borra el catálogo sin conocer las tablas de promociones, y "Obtener
  información" falla siempre con la llave foránea de `promotion_products`.
  **La reversión es restaurar el respaldo del paso 3** (ver abajo, "Regresar
  al respaldo"). Ese respaldo es de ANTES del despliegue: se pierde lo
  capturado después que no se haya transmitido, y las cotizaciones (que el
  respaldo no conoce). Transmitir antes lo que se pueda.
- **Posterior a las promociones pero anterior a las cotizaciones (`9c53e2e`):**
  `checkout`, pero **antes, con el servicio detenido, se borran las
  cotizaciones** (abajo). El código anterior no sabe qué es una cotización:
  una guardada con cliente la trata como pedido capturado, el panel dice
  "Transmítelo" y "Transmitir pedidos" la manda al ERP como **venta real**
  (15ª auditoría).
- **Posterior a las cotizaciones:** `checkout` y listo (las migraciones de
  este lote son compatibles hacia atrás, ver abajo).

**Borrar las cotizaciones, con el servicio DETENIDO.** Con el servicio
arriba, una cotización guardada entre el borrado y el reinicio la vería el
código viejo como pedido. Y la comprobación va en SQL, porque el código viejo
no tiene `Order.estimate` y no se podría repetir después del `checkout`:

```bash
sudo systemctl stop fecego-rueda-negocios
bin/rails runner 'puts Order.transaction { Order.purge_estimates! }'   # cuántas se borraron
bin/rails runner 'puts ActiveRecord::Base.connection.select_value("SELECT count(*) FROM orders WHERE document = \x27estimate\x27")'   # 0
```

Es el mismo borrado que hacen "Obtener información" y "Cerrar rueda". Las
cotizaciones solo viven en la laptop y no se recuperan: avisar a los
capturistas antes. Después, con el servicio todavía detenido:

```bash
git checkout <sha anterior>
bin/rails tailwindcss:build     # el CSS también hay que rehacerlo al revertir
sudo systemctl start fecego-rueda-negocios
```

**Regresar al respaldo** (sha anterior a las promociones). El procedimiento de
`docs/instalacion-laptop.md` ("Restaurar"), con dos diferencias: el código se
regresa ANTES de arrancar, y la copia **no se migra** — el respaldo ya tiene
el esquema del sha viejo, y migrarlo le pondría el del nuevo.

Los comandos no dan por hecho la terminal del paso 3: cargan el `.env`, toman
la ruta anotada y van encadenados con `&&`, para que una restauración fallida
no siga hasta arrancar la app contra una base vacía. La base lleva fecha en
el nombre: un `rueda_restore` de una prueba anterior haría fallar el
`createdb`.

```bash
cd ~/Proyectos/fecego-rueda-negocios
set -a; source .env; set +a
DUMP=<ruta anotada en el paso 3>
RESTORE_DB=rueda_restore_$(date +%Y%m%d_%H%M)
sudo systemctl stop fecego-rueda-negocios &&
  pg_restore -l "$DUMP" > /dev/null &&
  createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$RESTORE_DB" &&
  pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$RESTORE_DB" --no-owner "$DUMP" &&
  git checkout <sha del paso 1> &&
  bin/rails tailwindcss:build &&
  echo "Listo: pon DB_NAME=$RESTORE_DB en el .env y arranca el servicio"
# DB_NAME=<el que imprimió> en el .env
sudo systemctl start fecego-rueda-negocios
```

**Revertir el código NO deshace las migraciones.** Qué hacer depende de QUÉ
migraciones traiga el lote:

- **Columnas nuevas y nullable** (las del lote del 2026-09-29/30:
  `supplier_id`/`brand_id` de las partidas y `captured_at` del pedido; y las
  del 2026-10-08: la tabla `price_overrides` y `price_from_file`/
  `erp_unit_price` de las partidas, con valor por omisión; y la del
  2026-10-09: `pieces_per_box` del producto, del Cotizador; y la del
  2026-10-27: `orders.document` con default "sale", `client_id` y `kind`
  nullable, el CHECK `orders_sale_requires_client` y
  `settings.last_estimate_number`): **el checkout basta, sin rollback.**
  El código anterior ignora las columnas que no
  conoce — comprobado en la 12ª auditoría: sin migraciones pendientes,
  `capture!` y "Obtener información" corren completos. Un `db:rollback` aquí
  borraría, sin necesidad, el proveedor y la marca de los productos nuevos y
  los precios cargados con su rastro.
- **Ojo con la del 2026-10-27 (cotizaciones):** el código anterior convive
  con las columnas —todo pedido viejo lleva `document = sale`—, pero NO con
  los datos. Por eso el borrado de cotizaciones de arriba es obligatorio, y
  no basta con pedirlo desde las pantallas: el equipo-servidor no puede
  descartar cotizaciones (solo las consulta), y cada capturista solo ve las
  suyas. Sin él, además de la venta falsa, una cotización genérica tumba el
  reporte de pedidos del código anterior y aborta "Transmitir pedidos" a
  medias.

  **Con "Cambiar precios" hay dos cosas que hacer ANTES del checkout** (13ª
  auditoría): (1) **"Quitar precios cargados"**: el código anterior ni los lee
  ni los borra al cerrar la rueda, y reaparecerían solos al volver a desplegar
  sobre la misma rueda; (2) **transmitir antes lo capturado a precio de
  archivo**: el `Sync::Up` anterior no manda `precio_archivo`/`precio_erp`, y
  la evidencia se escribe una sola vez — lo que se transmita después de
  revertir llega al ERP con el precio de archivo y sin rastro de que lo fue.
- **Tablas o llaves foráneas que el código viejo no contempla** (las de
  promociones): ahí la app vieja choca con ellas —"Obtener información" falla
  al purgar el catálogo—. Es el caso de regresar a un sha anterior a
  `2bcc943`, y la salida es la de arriba: restaurar el respaldo del paso 3.

**Y se revierten las DOS puntas, no solo la laptop.** Con la API nueva y la
laptop vieja, cada pedido que se transmita deja su evidencia en el ERP sin
capturista, sin fechas de la laptop y sin las descripciones — y como la
evidencia se escribe una sola vez, así se queda. Las gemas de más instaladas no
estorban — Bundler solo se queja de las que faltan.

**Un pedido rechazado con "Error interno del servidor; no se guardó nada"** no
es la laptop: el motivo está en el log de la API, **en el servidor**.

```bash
sudo journalctl -u fecego-rueda-api --since today | grep internal_error | tail -3
```

Si dice `Sequel::DatabaseDisconnectError` con *"terminating connection due to
administrator command"*, el Postgres del ERP se reinició o le mataron las
conexiones. `OrderCreate` envuelve todo en una transacción, así que no quedó
nada a medias: **basta volver a transmitir**.

**Una corrida atorada en "en progreso"** se destraba sola al recargar el panel
(consulta su estado cada 3 s) cuando su proceso murió. **No** cuando puma se
reinició en caliente (`touch tmp/restart.txt`, `bin/rails restart`, SIGUSR2):
el hilo del job muere pero el pid sigue vivo, y el barrido la respeta —la
captura queda pausada en todo el salón (17ª auditoría). Ahí, o si de verdad
quedó colgada:

```bash
bin/rails runner '
  r = SyncRun.running.first
  r&.finish_interrupted!
  puts r ? "cerrada ##{r.id} (#{r.kind}, desde #{r.started_at})" : "no había ninguna"
'
```

## La API (`rueda-api`) es aparte

Vive en `fecegowstest`, no en la laptop, y se actualiza sola:

```bash
ssh fecego@fecegowstest
cd ~/fecego-rueda-api
git log --oneline -1          # anota de dónde venías
git pull origin master
bundle install                # solo si cambió el Gemfile (git diff --stat <de dónde venías> -- Gemfile.lock)
sudo systemctl restart fecego-rueda-api
curl -s http://localhost:7011/health
```

**Si el lote cambió `db/erp-prerequisitos.sql`, eso va ANTES del restart**
(procedimiento en `docs/instalacion-vm-produccion.md` de `rueda-api`). El del
Cotizador (2026-10-10) lo cambió: le da lectura de `alm_ficha_tecnica` al
usuario de la API. Sin ella, `/health` responde `"permiso de lectura en
alm_ficha_tecnica"` y "Obtener información" falla completo — no solo la caja.

**El lote de las cotizaciones (2026-10-28) también toca la API**, aunque la
laptop no la necesita para funcionar: la API rechaza cualquier pedido cuya
clave lleve el segmento `COT-` ("es una cotización, no un pedido"). Es la red
por si una cotización llegara a transmitirse, **pero solo desde una laptop
que manda la clave** (`472a6a6`, 2026-09-08, en adelante): el código anterior
no la manda, y para la API ese pedido no trae segmento que mirar. Tras
revertir a un sha anterior a `472a6a6`, la única red es el borrado de
cotizaciones de "Si algo sale mal" (16ª auditoría). `c63a18a`, el de la laptop
al 2026-10-29, sí la manda. Por lo mismo, una rueda con prefijo `COT`
haría que la API rechazara todas sus ventas: la laptop lo evita sacando esos
pedidos con el respaldo `RN` y avisándolo en el panel. Comprobación: en el log de la API no debe aparecer ese rechazo; si
aparece, alguien intentó mandar una cotización.

**Si el lote toca las dos puntas, la API va primero — y la laptop va detrás en
la misma ventana.** No se opera con una versión de API y otra de laptop (regla
con FECEGO). Una laptop nueva contra una API vieja se queda sin lo que la API
todavía no exporta —las promociones, por ejemplo— y el capturista no puede
compensarlo a mano. Y al revés **tampoco es inocuo desde el reparto**: la API
nueva parte el pedido aunque venga de una laptop vieja, que guardaría un folio
de varios sin enterarse (10ª auditoría). Mientras las dos no estén parejas: ni
transmitir ni obtener información.

Puerta de paso del lado de la API, cuando el lote toca el export:

```bash
curl -s http://localhost:7011/ruedas/3/export | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  print('promociones:', len(d.get('promotions', []))); \
  print('productos:', len(d['products'])); \
  print('con piezas por caja:', sum(1 for p in d['products'] if p.get('pieces_per_box')))"
```
