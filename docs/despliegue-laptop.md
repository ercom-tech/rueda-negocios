# Actualizar la laptop del evento

Cómo llevar a la laptop-servidor una versión nueva. Para instalarla desde cero,
ver `docs/instalacion-laptop.md`.

> **Esta guía vive en el repo a propósito.** Antes era un archivo suelto en el
> directorio temporal de la sesión, y se perdió: cuando hizo falta desplegar no
> había contra qué comparar y el procedimiento quedó en la memoria de nadie
> (9ª auditoría). Si cambia el procedimiento, se cambia aquí.

## Lo que hay que saber antes de tocar nada

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
| 3 | `git pull origin master` | `git log --oneline -1` coincide con la versión que se quería |
| 4 | `bundle install` | `bundle check` → `The Gemfile's dependencies are satisfied` |
| 5 | `bin/rails db:migrate` | Sin error. Es inofensivo aunque no haya migraciones |
| 6 | `bin/rails tailwindcss:build` | Termina con `Done in …`. El CSS compilado **no** viaja en el repo (`app/assets/builds/` está en `.gitignore`), así que sin este paso las clases nuevas no existen. Para comprobar que una clase concreta entró, busca su **declaración** y no su nombre: en el archivo las clases van escapadas (`.min-w-\[18rem\]`) y un `grep` del nombre tal cual devuelve 0 aunque esté — p. ej. `grep -c 'min-width:18rem'` → `1` |
| 7 | `sudo systemctl restart fecego-rueda-negocios` | `systemctl status fecego-rueda-negocios` → `active (running)`, sin reinicios acumulándose |
| 8 | Abrir la app en el navegador | Entra al menú, sin error |

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

```sql
SELECT consecutivo, id_producto, id_promocion, promo_porcentaje,
       descto_porcentaje, consec_origen_promo, total
FROM fecego.vta_pedido_detalle
WHERE id_empresa = 1 AND clave_pedido = '<folio devuelto>'
ORDER BY consecutivo;
```

Los consecutivos van **1, 2, 3…** en el orden en que se capturaron (la pantalla
los muestra al revés a propósito; el ERP no). Una partida de regalo lleva
`promo_porcentaje = 100`, `total = 0.00` y `consec_origen_promo` apuntando a la
partida que la detonó.

## Si algo sale mal

```bash
git checkout <sha anterior>
bin/rails tailwindcss:build     # el CSS también hay que rehacerlo al revertir
sudo systemctl restart fecego-rueda-negocios
```

No queda estado que deshacer mientras el lote no traiga migraciones (las
migraciones **no** se revierten solas: si el lote las trae, hay que decidir
caso por caso). Las gemas de más instaladas no estorban — Bundler solo se queja
de las que faltan.

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

**Si el lote toca las dos puntas, la API va primero.** Una laptop nueva contra
una API vieja se queda sin lo que la API todavía no exporta —las promociones,
por ejemplo— y el capturista no puede compensarlo a mano. Al revés es
tolerable: la API nueva sigue respondiendo a la laptop vieja.

Puerta de paso del lado de la API, cuando el lote toca el export:

```bash
curl -s http://localhost:7011/ruedas/3/export | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  print('promociones:', len(d.get('promotions', []))); \
  print('productos:', len(d['products']))"
```
