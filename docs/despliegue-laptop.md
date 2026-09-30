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

`schema: "ok"` significa que están las cuatro columnas y las dos tablas de la
evidencia (`vta_pedido_rueda` y su detalle). Si falta algo, responde 503 y lo
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

**Dos pasos que parecen opcionales y no lo son** (medido en la 9ª auditoría):

- **Sin `bundle install`, la app NO ARRANCA.** No es una pantalla rota: Bundler
  falla en `Bundler.setup`, antes de cargar Rails, y con `Restart=always` el
  servicio entra en bucle. En las tablets se ve "No se puede acceder a este
  sitio" y nada en la app dice por qué — hay que ir a `journalctl`.
- **Sin `systemctl restart`, los initializers nuevos no existen.** El reload de
  development recarga `app/`, pero **no** `config/initializers/`. Un MIME sin
  registrar hace que la pantalla que lo usa dé 500 — y como todo lo demás sí
  tomó el código nuevo, parece que el despliegue salió bien y que la pantalla
  nueva nació rota.

**Hazlo desde la oficina, con internet, y con la rueda cerrada.** El peor orden
posible es `git pull` en el salón sin conexión: el pull funciona, el
`bundle install` falla por DNS, y el proceso viejo sigue vivo **hasta el primer
reinicio** — momento en que el sitio muere y la única salida es revertir.

## Los pasos

```bash
cd ~/Proyectos/fecego-rueda-negocios
```

| # | Paso | Qué comprobar después |
|---|---|---|
| 1 | `git status --short` | Vacío. Si sale `Gemfile.lock` modificado (bundler reescribe `BUNDLED WITH`), `git checkout Gemfile.lock` antes de seguir |
| 2 | `bin/rails runner 'puts SyncRun.running.count'` | `0`. Si no, esperar: reiniciar a media corrida la mata (los jobs viven en hilos de puma) |
| 3 | Respaldo de la BD (comandos en `docs/instalacion-laptop.md`, "Respaldo de la BD de la app") | `pg_restore -l "$DUMP"` lista tablas. Es la única vuelta atrás del paso 6: `git checkout` no deshace una migración |
| 4 | `git pull origin master` | `git log --oneline -1` coincide con la versión que se quería |
| 5 | `bundle install` | `bundle check` → `The Gemfile's dependencies are satisfied` |
| 6 | `bin/rails db:migrate` | Sin error. Es inofensivo aunque no haya migraciones |
| 7 | `bin/rails tailwindcss:build` | Termina con `Done in …`. El CSS compilado **no** viaja en el repo (`app/assets/builds/` está en `.gitignore`), así que sin este paso las clases nuevas no existen. Para comprobar que una clase concreta entró, busca su **declaración** y no su nombre: en el archivo las clases van escapadas (`.min-w-\[18rem\]`) y un `grep` del nombre tal cual devuelve 0 aunque esté — p. ej. `grep -c 'min-width:18rem'` → `1` |
| 8 | `sudo systemctl restart fecego-rueda-negocios` | `systemctl status fecego-rueda-negocios` → `active (running)`, sin reinicios acumulándose |
| 9 | Abrir la app en el navegador | Entra al menú, sin error |

## Comprobación después de desplegar

Lo mínimo, en el navegador de la laptop:

- **Menú → Reportes**: las tarjetas habilitadas abren sin error.
- **Levantamiento de pedido**: agregar una partida; el contador del buscador
  sube y la partida aparece donde debe.
- **Panel del servidor**: "Obtener información" termina en "✓ Listo" y el panel
  se destraba **solo**, sin recargar (el estado se consulta cada 3 s).
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

```bash
git checkout <sha anterior>
bin/rails tailwindcss:build     # el CSS también hay que rehacerlo al revertir
sudo systemctl restart fecego-rueda-negocios
```

**Revertir el código NO deshace las migraciones.** Qué hacer depende de QUÉ
migraciones traiga el lote:

- **Columnas nuevas y nullable** (las del lote del 2026-09-29/30:
  `supplier_id`/`brand_id` de las partidas y `captured_at` del pedido): **el
  checkout basta, sin rollback.** El código anterior ignora las columnas que no
  conoce — comprobado en la 12ª auditoría: sin migraciones pendientes,
  `capture!` y "Obtener información" corren completos. Un `db:rollback` aquí
  solo borraría, sin necesidad, el proveedor y la marca de los productos nuevos.
- **Tablas o llaves foráneas que el código viejo no contempla** (las de
  promociones, en su momento): ahí la app vieja choca con ellas —"Obtener
  información" fallaba al purgar el catálogo—, y hace falta `bin/rails
  db:rollback STEP=n` **antes** del checkout, sabiendo que se pierde lo que esas
  columnas guardaban. Mejor: restaurar el respaldo del paso 3.

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
(consulta su estado cada 3 s). Si de verdad quedó colgada:

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
sudo systemctl restart fecego-rueda-api
curl -s http://localhost:7011/health
```

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
  print('productos:', len(d['products']))"
```
