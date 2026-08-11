# rueda-negocios

Aplicación web para capturar pedidos durante las **ruedas de negocios** de
FECEGO, con operación **offline** en el sitio del evento.

## Idioma

El usuario habla **español de México**. Comunícate siempre en ese registro:
usar **tú** (no *vos*, no *vosotros*); evitar léxico ibérico (*vale*, *guay*,
*ordenador*, *móvil*, *coche*) y rioplatense (*che*, *bárbaro*, *re-*).
Registro neutro-mexicano por defecto. (Código, commits y comentarios van en
el idioma que el proyecto use.)

## Forma de trabajo — flujo PAIVD

Todo cambio sigue el ciclo **P**roponer → **A**probar → **I**mplementar →
**V**alidar → **D**ocumentar:

1. **Proponer** — describir el cambio (qué y por qué) antes de tocar archivos.
2. **Aprobar** — esperar autorización explícita del usuario en ese turno.
3. **Implementar** — aplicar el cambio ya aprobado.
4. **Validar** — verificar que funciona (tests, ejecución, revisión).
5. **Documentar** — registrar la decisión/aprendizaje en `memory.md`; lo que
   quede pospuesto, en `backlog.md`.

Regla dura: **no uses Edit/Write sin aprobación previa del usuario en el
turno.** Bash de inspección (git, ls, grep, psql) y Read son libres.

**Publicar es un paso aparte:** `git commit` y `git push` requieren aprobación
explícita en el turno. Un "dale" autoriza implementar, no publicar.

## Convenciones (se cargan con este archivo)

@docs/convenciones-visuales.md
@docs/convenciones-codigo.md

## Naturaleza del proyecto

Proyecto **independiente y autónomo**. NO es aditivo ni una extensión del
sistema `fecego-b2b`. Los proyectos b2b son solo **referencia** de stack,
patrones e infraestructura.

## Contexto de negocio

Una **rueda de negocios** es un evento donde proveedores de FECEGO agendan
citas con clientes para ofrecer productos con **beneficios/precios especiales
válidos solo durante la rueda**. Las ventas son de FECEGO: los pedidos deben
aterrizar en el **ERP** para seguir el flujo operativo normal (surtido,
embarque, entrega, cobro). Un evento puede durar más de un día.

Los **capturistas** usan la app para: login, captura de pedidos, registro de
asistencia de clientes y consulta de reportes — todo **offline** durante el
evento.

## Arquitectura

Modelo **una laptop = servidor LAN**:

- Una laptop corre la app + su Postgres local y hace de servidor en la red
  local del evento. Los demás equipos apuntan a ella con solo un navegador.
- El "offline" se resuelve a nivel de red: nada depende de internet durante
  el evento.
- El sync con el ERP ocurre cuando la laptop tiene conexión (por defecto,
  **desde la oficina** antes/después del evento).

### Piezas (2 proyectos)

1. **`rueda-negocios`** (este repo — corre en la laptop-servidor)
   Rails 8 + Hotwire + Tailwind + Postgres local + bcrypt. UI para
   capturistas en LAN. Incluye tareas **rake de sync** (down/up).

2. **`rueda-api`** (repo aparte — corre en la VM on-prem, junto al ERP)
   Sinatra 4 + Sequel + pg (patrón api-v2). Habla directo con la BD del ERP.
   - **Export del dataset** de la rueda → alimenta el sync-down.
   - **Creación de pedidos en el ERP** → endpoint nuevo (no existe hoy;
     entregable de mayor riesgo).

### Flujo de sync

- **Antes del evento (oficina):** la laptop descarga el dataset (usuarios,
  membresías capturista↔proveedor/marca, vendedores, clientes, proveedores,
  marcas, productos, precios/beneficios, definición de la rueda) desde
  `rueda-api` → puebla Postgres local.
- **Durante (offline, LAN):** pedidos con **folio local** (`RN-000123`), estado
  `draft` mientras se capturan y `captured` al finalizarse.
- **Después / entre días (oficina):** la laptop transmite pedidos a
  `rueda-api` → inserción en ERP → devuelve folio ERP → se marca
  `transmitido`. Idempotente y reintentable.

El transporte del sync es **agnóstico**: URL + credenciales configurables,
para que funcione en LAN interna o vía internet sin cambiar código. El
endurecimiento de seguridad (HTTPS, tokens, allowlist, proxy en AWS) queda
para una **fase posterior de strengthening**.

## Stack (referencia fecego-b2b)

Ruby 3.3.7. Rails 8 + Hotwire + Tailwind (app); Sinatra 4 + Sequel + pg
(API); Rake + Sequel para procesos de sync (patrón sync-v2/upload-v2);
Postgres 16; bcrypt.

## Infraestructura

- **On-prem:** VM Linux con **ERP Postgres 16** (fuente y destino final);
  VM Linux con la API b2b (aquí vivirá `rueda-api`).
- **AWS:** 2 VMs Linux (backend/frontend b2b) — disponibles para el borde
  TLS/proxy en la fase de strengthening.

## Referencias (patrones/stack, NO base de código)

- `/Users/gcalderon/Projects/fecego-b2b/` — api-v2, sync-v2, portal-v2,
  upload-v2, learning.
- Repo predecesor (cómo se leen pedidos hoy / paridad):
  `/Users/gcalderon/Work/ERCOM/Clientes/FECEGO/Proyectos/Portal B2B/Ruby/fecego-b2b-api`.

## Puntos abiertos / riesgos

Ver `backlog.md`.

## Dónde va cada cosa

Solo este archivo y sus imports se cargan solos; lo demás se consulta cuando
hace falta.

| Archivo | Contenido |
|---|---|
| `CLAUDE.md` (este) | Contrato: forma de trabajo, arquitectura, stack |
| `docs/convenciones-visuales.md` | Normas de UI y de los textos al usuario |
| `docs/convenciones-codigo.md` | Normas y trampas del stack |
| `memory.md` | Bitácora: decisiones y su porqué |
| `backlog.md` | Lo que falta implementar |
| `docs/erp-esquema-catalogos.md`, `docs/erp-esquema-pedidos.md` | Esquema del ERP |
| `docs/instalacion-laptop.md` | Instalación en la laptop-servidor |
| `docs/auditorias.md` | Cómo se audita el proyecto: método y dimensiones |
| `docs/auditorias-2026-07.md` | Historial de las 2 primeras auditorías (cerradas) |

Criterio: si es **norma que rige cada cambio**, va a las convenciones (que sí
se cargan); si es **el porqué de una decisión**, a `memory.md`; si es **algo
por hacer**, al backlog. Al cerrarse un renglón del backlog, el aprendizaje
pasa a `memory.md` y el renglón **se borra** — el backlog es lo que falta, no
un histórico.
