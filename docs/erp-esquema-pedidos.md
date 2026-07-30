# Esquema ERP — alta de pedidos (sync-up)

Cómo se **inserta un pedido** en el ERP de FECEGO (Postgres, esquema `fecego`)
para el **sync-up**: `rueda-negocios` transmite los pedidos capturados offline →
`rueda-api` los inserta en el ERP.

Descubierto por inspección del ERP local de desarrollo (`psql -p 1702 -d fecego`,
el mismo restore que usa el b2b) + el lado de LECTURA de api-v2
(`app/queries/orders.rb`, modelos `Order`/`OrderItem`). Confirma también el
manejo fiscal/IVA que estaba pendiente.

## El ERP ya maneja pedidos "transmitidos" (ruta)

`vta_pedido` tiene `transmitido`, `clave_pedido_ruta`, `id_usuario_transmision`,
`fecha_transmision`, `hora_transmision`. El ERP ya recibe pedidos capturados
afuera y transmitidos (≈49% de los pedidos traen `clave_pedido_ruta`, vigente
2019→2026). La rueda sigue ese patrón: se inserta el pedido y se marca
`transmitido`.

- **`clave_pedido_ruta` NO es nuestro:** lo llena la **planeación de ruta** de
  FECEGO en su operación. En el alta de la rueda se deja nulo.
- Nuestro `Order.local_folio` es **solo referencia offline** en la app; no se
  envía al ERP.

## Tablas

### Cabecera → `fecego.vta_pedido`
- **PK compuesta:** `(id_empresa, clave_cliente, fecha_pedido, hora_pedido)` — el
  pedido se identifica por empresa + cliente + **fecha + hora de captura**.
- **`clave_pedido varchar(6)` NOT NULL** = folio oficial (prefijo 2 letras + 4
  dígitos, ej. `ZA0959`).
- **NOT NULL:** `id_empresa` (def 1), `clave_cliente`, `fecha_pedido`,
  `hora_pedido`, `clave_pedido`, `id_vendedor_cliente_pos` (0), `id_usuario_caja`
  (0), `id_estatus_cliente` (0), `facturado_linux` (false). El resto default.

### Detalle → `fecego.vta_pedido_detalle`
- **PK:** `(id_empresa, clave_cliente, fecha_pedido, hora_pedido, consecutivo)`.
- Campos: `id_producto` (SKU=`com_producto.id_producto`), `cantidad`, `precio`,
  `subtotal`, `descto_porcentaje`, `descto_monto`, `iva_porcentaje`, `iva_monto`,
  `total`, `clave_pedido` (mismo folio), `baja=false`, auditoría.

## Folio `clave_pedido` — se asigna EN LA TRANSMISIÓN (no antes)

`rueda-api` lo genera al insertar, no la app ni antes:

**`clave_pedido` = prefijo + consecutivo:**
- **Prefijo** (2 letras) = `cnf_persona.prefijo` del **capturista** (ej. persona
  262 ZABDIEL → `ZA`; sus pedidos son `ZA####`). Se resuelve por `id_persona`.
- **Consecutivo** = parte numérica del **último `clave_pedido` con ese prefijo** + 1,
  a 4 dígitos:
```sql
SELECT COALESCE(MAX(substring(clave_pedido FROM 3)::int), 0) + 1
FROM fecego.vta_pedido
WHERE substring(clave_pedido FROM 1 FOR 2) = :prefijo;
-- clave_pedido = :prefijo || lpad(consecutivo, 4, '0')
```
- Hacerlo con **lock / transacción** para evitar folios duplicados en
  transmisiones concurrentes. La parte numérica es de 4 dígitos y el ERP reutiliza
  folios de pedidos cancelados.

El `clave_pedido` resultante se devuelve y se guarda en nuestro `erp_folio`.

## Fiscal / IVA (RESUELTO)

Desglose **por partida**: `iva_porcentaje` + `iva_monto`, `descto_porcentaje` +
`descto_monto`, `subtotal`, `total`; y en cabecera `subtotal`, `descto_monto`,
`iva_monto`, `total`. Fórmula estándar (total = subtotal − descuento + IVA), con
**IVA por producto** desde la tabla de precios. Coincide con `OrderItem` y el PDF. ✔

## Valores del alta (definidos)

- `estatus_actual` = **`CAPTUR`**.
- `id_vendedor` = **el vendedor del cliente** (`vta_cliente.id_vendedor`), no el
  capturista.
- `bodega` = **no se usa**.
- `remision` = false (Factura) / true (Remisión).
- `transmitido` = true + `id_usuario_transmision`/`fecha`/`hora` al transmitir.
- `id_empresa` = 1; `baja` = false; auditoría (`id_usuario_crea`, `fecha/hora_crea`).

## Mapeo con nuestro modelo local

| Nuestro (`Order`/`OrderItem`) | ERP (`vta_pedido` / `_detalle`) |
|---|---|
| `client.erp_client_key` | `clave_cliente` |
| `created_at` (fecha/hora) | `fecha_pedido` + `hora_pedido` |
| — (referencia offline) | `local_folio` (no se envía) |
| (asigna rueda-api en transmisión) | `clave_pedido` → `erp_folio` |
| `kind` invoice/remission | `remision` false/true |
| `client_tax_profile.rfc` | `rfc` |
| `cfdi_use.code` | `"c_UsoCFDI"` |
| `client_branch` (sucursal) | `sucursal` |
| `client.salesperson.erp_salesperson_id` | `id_vendedor` |
| `observations` | `observaciones` |
| `dividir_facturas` (NUMERIC(18,6); importe máximo por factura al facturar, 0 = no dividir — se captura en el paso 1, solo Factura) | `dividir_facturas` |
| totales | `subtotal`/`descto_monto`/`iva_monto`/`total` |
| item: `code`/`quantity`/`unit_price`/`discount_%`/`tax_%` (+ montos) | `id_producto`/`cantidad`/`precio`/`descto_porcentaje`/`iva_porcentaje` (+ `descto_monto`/`iva_monto`/`subtotal`/`total`) |

## Pendientes (confirmar con FECEGO)

1. **Campos de configuración** de la cabecera: `"c_FormaPago"`, `"c_MetodoPago"`,
   `condicion_pago`, `tipo_precio`, `id_negociaciontipo`, `id_enviotipo`. ¿De dónde
   salen para un pedido de rueda (defaults del cliente en el ERP, o fijos)?
   Hoy usan defaults en `OrderCreate::HEADER_DEFAULTS` (moda del ERP).

## Resuelto

- **Idempotencia** al reintentar la transmisión: `OrderCreate.find_existing`
  busca por la PK de negocio `(id_empresa, clave_cliente, fecha_pedido,
  hora_pedido)` y devuelve el folio con `idempotent: true` sin reinsertar.
- **Colisión de la llave de idempotencia** (2ª auditoría): la PK de negocio va
  a granularidad de **segundo** — dos pedidos distintos del mismo cliente
  capturados en el mismo segundo harían match. `find_existing` trae además
  `total` y # de partidas: si el contenido del pedido existente **difiere**
  (total > $0.01 o distinto # de partidas), la API responde **422 "colisión de
  idempotencia"** en vez de regalar el folio ajeno; el sync-up lo marca fallido
  y visible (remedio: recapturar). Restricción confirmada por el usuario:
  **el ERP de FECEGO NO tolera microsegundos en `hora_pedido`** — por eso la
  solución es detección, no mayor granularidad.
