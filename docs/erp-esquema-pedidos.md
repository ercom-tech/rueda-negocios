# Esquema ERP — alta de pedidos (sync-up)

Cómo se **inserta un pedido** en el ERP de FECEGO (Postgres, esquema `fecego`)
para el **sync-up**: `rueda-negocios` transmite los pedidos capturados offline →
`rueda-api` los inserta en el ERP.

Descubierto por inspección del ERP local de desarrollo (`psql -p 1702 -d fecego`,
el mismo restore que usa el b2b) + el lado de LECTURA de api-v2
(`fecego-b2b-api-v2/app/queries/orders.rb` — otro repo, no este). Confirma también el
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
- **`clave_pedido varchar(6)` NOT NULL** = folio oficial. Mide **siempre 6**, y
  el ancho del consecutivo se **deriva** del prefijo: 2 caracteres → 4 dígitos
  (`ZA0959`), 1 carácter → 5. No es "prefijo + 4 dígitos" fijo.
  - El ERP lo arma por **dos ramas**: si la sucursal tiene `venta_prefijo`
    (sucursales 3, 5, 6, 8…), 1 carácter + contador en `cnf_sucursal.venta_consec`;
    si no (**1 = MATRIZ**, que es por donde insertamos nosotros), el `prefijo`
    de `cnf_persona` (varchar(2)). Medir la regla en la rama equivocada da una
    certeza falsa: en la nuestra son 514,660 folios de 2+4 sin una excepción.
  - **El prefijo se agota:** al llegar a 9999 no cabe otro folio. `rueda-api`
    lo rechaza con un 422 accionable ("pide que le asignen una clave nueva")
    en vez de dejar que reviente el INSERT con un 500 opaco. FECEGO ya rota
    prefijos agotados como práctica (`cnf_persona_prefijo_hist`).
  - **`MAX + 1` es la elección correcta** aunque el ERP recicle folios (hay
    1,765 `clave_pedido` duplicados y ningún UNIQUE): los huecos del ERP
    quedan por debajo del máximo y nosotros siempre emitimos por encima, así
    que no podemos colisionar. Depende de que los capturistas de rueda usen su
    bloque reservado de prefijos y no uno con actividad viva del ERP.
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

**`clave_pedido` = prefijo + consecutivo, siempre 6 caracteres:**
- **Prefijo** = `cnf_persona.prefijo` del **capturista** (`varchar(2)`; ej.
  persona 262 ZABDIEL → `ZA`, sus pedidos son `ZA####`). Se resuelve por
  `id_persona`.
- **Consecutivo** = parte numérica del **último `clave_pedido` con ese prefijo**
  + 1, rellenado hasta completar los 6 caracteres (`6 − len(prefijo)` dígitos).
```sql
-- El filtro de sufijo numérico NO es opcional: hay folios cuya parte final no
-- lo es, y sin él el ::int revienta con "invalid input syntax for integer".
-- El LIKE hace la consulta sargable: sin él son ~135 ms por folio (1.2M de
-- filas escaneadas); con él, ~27 ms.
SELECT COALESCE(MAX(substring(clave_pedido FROM 3)::int), 0) + 1
FROM fecego.vta_pedido
WHERE id_empresa = 1
  AND clave_pedido LIKE :prefijo || '%'
  AND substring(clave_pedido FROM 1 FOR 2) = :prefijo
  AND substring(clave_pedido FROM 3) ~ '^[0-9]+$';
-- clave_pedido = :prefijo || lpad(consecutivo, 6 - length(:prefijo), '0')
```
- Va con **lock** (`pg_advisory_xact_lock` por prefijo, dentro de la
  transacción) para evitar folios duplicados en transmisiones concurrentes.
- **Si el consecutivo ya no cabe**, `rueda-api` responde 422 con un mensaje
  accionable en vez de dejar que el INSERT reviente contra el `varchar(6)`.

El `clave_pedido` resultante se devuelve y se guarda en nuestro `erp_folio`.

## Fiscal / IVA (RESUELTO)

Desglose **por partida**: `iva_porcentaje` + `iva_monto`, `descto_porcentaje` +
`descto_monto`, `subtotal`, `total`; y en cabecera `subtotal`, `descto_monto`,
`iva_monto`, `total`. Fórmula estándar (total = subtotal − descuento + IVA), con
**IVA por producto** desde la tabla de precios. Coincide con `OrderItem` y el PDF. ✔

## Valores del alta (definidos)

- `estatus_actual` = **`CAPTUR`**.
- `renglones` = **# de partidas** del pedido. Invariante dura: en 1.2M de
  pedidos históricos SIEMPRE es el conteo del detalle — dejarlo en 0 hace que
  el ERP no refleje bien el pedido (bug encontrado 2026-07-30).
- `id_sucursal_crea` = **1** (matriz), como todo pedido capturado en oficina.
- **`fecha_crea`/`hora_crea` = el instante de la CAPTURA**, no el de la
  transmisión (decisión de FECEGO, 2026-08-11). La rueda es offline y el sync
  corre desde la oficina: una rueda del viernes transmitida el lunes dejaba
  todos sus pedidos creados en lunes, y el ERP tiene un índice dedicado
  (`vta_pedido_idx2` por `id_sucursal_crea, fecha_crea`), así que cualquier
  corte de captura por día los agrupaba en el día de oficina. El momento de la
  transmisión no se pierde: va en `fecha_transmision` / `hora_transmision`.
  - **Matiz medido:** en el ERP, `fecha_crea = fecha_pedido` en el 99.69% de
    los pedidos, pero `hora_crea = hora_pedido` solo en el 5%. En sus pedidos
    nativos de rueda, `hora_crea` es **idéntica a `hora_transmision`** — porque
    el ERP transmite el mismo día y ahí "crear" y "transmitir" coinciden. Ese
    patrón no cubre nuestro caso; mezclar la fecha de captura con la hora de la
    transmisión daría un sello incoherente (viernes + reloj del lunes), así que
    las dos van del mismo instante.
- **Horas sin microsegundos:** `hora_crea` (cabecera y detalle) va a segundo —
  llega del payload como `"HH:MM:SS"`; el ERP no tolera micros en horas de
  captura. Excepción: `hora_transmision` SÍ trae micros en el propio ERP y se
  deja igual (`CURRENT_TIME`).
- `observaciones` sin texto = **`' '`** (un espacio, la moda del ERP; `''`
  casi no existe en el histórico).
- `id_vendedor` = **el vendedor del cliente** (`vta_cliente.id_vendedor`), no el
  capturista. El export trae los vendedores de la lista de la rueda **más los
  que traen sus clientes**: si el cliente venía con uno que nadie dio de alta
  en el evento, la app no podía resolverlo y el pedido llegaba con
  `id_vendedor = 0` — fuera del índice por vendedor, de sus reportes y de la
  comisión, sin error (1 de 1,245,383 pedidos del histórico está así). Si el
  payload llega sin él, `rueda-api` lo resuelve contra el cliente. 0 solo es
  legítimo cuando el cliente de veras no tiene vendedor (4 de 22,580).
- `bodega` = **no se usa**.
- `remision` = false (Factura) / true (Remisión).
- **Remisión: a nombre de quién va.** `consec_remision` es el consecutivo del
  perfil del cliente (`vta_cliente_has_remision.consecutivo`) y de él cuelga la
  cuenta referenciada de cobranza (`vta_remision_has_cuenta`). El ERP escribe
  el destinatario por una de **dos** vías y nunca por ninguna: ticket de
  mostrador con datos en línea (`remision_nombre`…) o flujo de pedido con este
  puntero. En 383,881 remisiones desde 2024, el cuadrante "ninguna de las dos"
  tiene **cero filas**. `0` solo es legítimo si el cliente no tiene ningún
  perfil dado de alta.
- **Remisión: RFC y uso de CFDI son fijos, no del cliente.** `rfc` =
  `XAXX010101000` (el genérico del SAT: 212,854 de 212,860 remisiones del flujo
  de pedido) y `c_UsoCFDI` = **`S01`** ("SIN EFECTOS LEGALES"). Ojo con la moda
  del histórico: P01 aparece mucho pero está **dado de baja** en
  `sat_uso_cfdi`. El RFC real del cliente NO va en una remisión — es lo que
  discrimina factura de remisión, y `rueda-api` lo impone por si la app lo
  dejara escapar.
- En una **factura**, `consec_remision` va en 0 (243,318 de 243,334).
- `dividir_facturas` es **campo de factura**: en remisión va en 0 por decisión
  nuestra, no del ERP (él sí acepta remisiones con monto: 3,079 de 110,577).
- **`total` se redondea a 2 decimales; los demás importes NO.** El ERP redondea
  `total` en cabecera y detalle (7 de 1,245,383 y 10 de 8,694,854 escapan),
  pero deja `subtotal`, `descto_monto` e `iva_monto` con más decimales (1.16M
  de cabeceras los tienen). El redondeo se aplica **al escribir**, no en la
  app: así el encabezado sigue cuadrando con sus partidas al centavo.
- **Ocho columnas van como cadena vacía, no NULL:** `clave_pedido_ruta`,
  `clave_cotizacion`, `coordenadas`, `latitud`, `longitud`, `factura`,
  `remision_nombre`, `remision_correo`. Son las que el ERP nunca deja nulas (0
  de 414,529 pedidos de 2025+). Importa porque `NULL = ''` **no es verdadero**:
  un reporte del ERP que filtre `WHERE factura = ''` —la mitad de sus pedidos
  la tiene vacía— no encontraría ninguno de los de la rueda. Las demás
  columnas sin default sí admiten NULL en el ERP y se dejan así.
- **Los importes de cada partida deben derivar de su cantidad y su precio.**
  `rueda-api` lo verifica renglón por renglón, no solo el encabezado contra la
  suma: con `cantidad: 1000` y `total: 116` el encabezado cuadra con la suma y
  almacén surtiría mil piezas contra un pedido de $116. El orden de
  operaciones es el de `OrderItem`: descuento e IVA sobre el importe de la
  partida, no sobre el precio unitario.
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
| `client_tax_profile.rfc` (solo Factura) | `rfc` (Remisión: `XAXX010101000`) |
| `cfdi_use.code` (solo Factura) | `"c_UsoCFDI"` (Remisión: `S01`) |
| `client_receipt_profile.erp_receipt_profile_id` (solo Remisión) | `consec_remision` |
| `client_branch` (sucursal) | `sucursal` |
| `client.salesperson.erp_salesperson_id` | `id_vendedor` |
| `observations` | `observaciones` (vacía → `' '`) |
| `order_items.count` | `renglones` |
| `dividir_facturas` (NUMERIC(18,6); importe máximo por factura al facturar, 0 = no dividir — se captura en el paso 1, solo Factura) | `dividir_facturas` |
| totales | `subtotal`/`descto_monto`/`iva_monto`/`total` |
| item: `product.erp_product_id`/`quantity`/`unit_price`/`discount_%`/`tax_%` (+ montos) | `id_producto`/`cantidad`/`precio`/`descto_porcentaje`/`iva_porcentaje` (+ `descto_monto`/`iva_monto`/`subtotal`/`total`) |

⚠️ `OrderItem#code` **no** es lo que viaja: desde 2026-07-30 es el código
FECEGO a 6 dígitos (`"017768"`, string) y existe solo para mostrarse. El
ERP espera el entero `com_producto.id_producto`, que es
`product.erp_product_id`.

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
