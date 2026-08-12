# rueda-negocios

App web para capturar pedidos durante las **ruedas de negocios** de FECEGO, con
operación **offline** en el sitio del evento.

Modelo **una laptop = servidor LAN**: una laptop corre la app + su Postgres local
y hace de servidor en la red del evento; los demás equipos solo necesitan un
navegador apuntando a ella. El sync con el ERP ocurre cuando la laptop tiene
conexión (por defecto, desde la oficina antes/después del evento).

Proyecto **independiente** (no aditivo al `fecego-b2b`; ese es solo referencia de
stack y patrones). La API que habla con el ERP vive en el repo aparte
[`rueda-api`](https://github.com/ercom-tech/rueda-api).

## Stack

Ruby 3.3.7 · Rails 8 + Hotwire (Turbo/Stimulus, importmap) + Tailwind v4 ·
Postgres 16 · bcrypt · Solid Queue (jobs) · dotenv-rails · prawn (PDF).

## Correr en desarrollo

> Para instalar en la laptop-servidor (Ubuntu): ver
> [docs/instalacion-laptop.md](docs/instalacion-laptop.md).

```sh
bundle install
cp .env.example .env        # ajusta credenciales de Postgres si hace falta
bin/rails db:prepare        # crea, migra y siembra (usuario server: servidor/rueda2026)
bin/dev                     # Rails + Tailwind watch (Procfile.dev)
```

`bin/rails db:seed` crea **solo** el usuario del rol `server`
(`servidor` / `rueda2026`, configurable por `SEED_SERVER_USERNAME` /
`SEED_SERVER_PASSWORD`). El resto del dataset (rueda, clientes, productos,
capturistas) se puebla con el **sync-down** desde `rueda-api`.

## Sync con el ERP

Requiere `rueda-api` accesible; configúrala en `.env`
(`RUEDA_API_URL`, `RUEDA_ID`).

- **sync-down** (poblar la BD local con los datos de la rueda, *reemplaza* el
  catálogo local): `bin/rails sync:down`
- **sync-up** (transmitir los pedidos capturados al ERP, idempotente):
  `bin/rails sync:up`

Ambos también se operan desde la UI: al entrar el usuario `server` ve un panel
para **elegir rueda**, **obtener información** (sync-down), **transmitir
pedidos** (sync-up), consultar **reportes** y **cerrar rueda**. Los dos syncs
corren en background (Solid Queue) y reflejan su estado en vivo (Turbo Streams).

**Cerrar rueda** elimina los pedidos ya transmitidos de la laptop, borra el
historial de corridas y libera la selección: es el paso obligado para cargar
otra rueda, y la única operación destructiva del panel. Las tres —obtener,
transmitir y cerrar— se bloquean si queda algún pedido que solo viva en la
laptop (borradores o capturados sin transmitir).

Mientras una corrida está viva, la captura se pausa: los capturistas ven un
aviso en vez de escribir sobre un catálogo que se está reemplazando.

## Roles

- **capturista** — captura pedidos y ve los suyos.
- **server** — opera el sync y ve todos los pedidos.

## Documentación

- `CLAUDE.md` — contexto de negocio, arquitectura y forma de trabajo (flujo PAIVD).
- `memory.md` — bitácora de decisiones y puntos abiertos.
- `docs/erp-esquema-catalogos.md` — esquema de lectura del ERP (sync-down).
- `docs/erp-esquema-pedidos.md` — esquema de alta de pedidos en el ERP (sync-up).

## Seguridad

El endurecimiento (HTTPS, tokens, allowlist, proxy en AWS) queda para una fase
posterior de *strengthening*. Ver `CLAUDE.md`.
