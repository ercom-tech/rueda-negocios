# Consultas de diagnóstico contra el ERP

Cuando el panel del servidor avisa de algo omitido, dice **cuántos** pero no
**cuáles**: el detalle vive en el ERP, no en la laptop. Aquí están las
consultas que lo responden, listas para pegar en `psql`.

También viven aquí las consultas que responden **qué pasó en la rueda** y que
solo el ERP puede contestar: lo que se capturó fuera de catálogo —la laptop lo
pierde al cerrar— y lo que se pidió pero no se facturó, que la laptop nunca
supo.

> **Las consultas de omisión replican los criterios de
> `rueda-api/app/queries/export.rb`.** Si el export cambia a quién deja entrar,
> hay que cambiarlas aquí también, o pasan a mentir sin que nada avise. Cada una
> dice de qué método sale.
>
> Todas usan `id_empresa = 1` y `id_rueda = 3`: ajusta la rueda. La de lo
> negado lleva además `id_marca`, y es la única que cruza al esquema
> **`fecego_cfdi`** — ojo con eso, porque `fecego` tiene tablas homónimas
> vacías.

## "N productos de promoción no llegaron al catálogo"

Replica el `WHERE` de `Export#products`. Un producto que una promoción incluye
solo llega al catálogo si es el genérico 999999, es regalo de la rueda, su
**marca** participa, o alguno de sus **proveedores** participa.

```sql
WITH r AS (SELECT 3::int AS id_rueda),
marcas AS (
  SELECT id_marca FROM fecego.cnf_rueda_negocios_marca
  WHERE id_empresa = 1 AND id_rueda = (SELECT id_rueda FROM r) AND baja = false),
provs AS (
  SELECT id_proveedor FROM fecego.cnf_rueda_negocios_proveedor
  WHERE id_empresa = 1 AND id_rueda = (SELECT id_rueda FROM r) AND baja = false),
promo AS (
  SELECT p.id_promocion, p.clave, p.nombre
  FROM fecego.vta_promocion p
  WHERE p.id_empresa = 1 AND p.id_rueda_negocio = (SELECT id_rueda FROM r)
    AND p.canal_venta = 'RUN' AND p.baja = false AND p.desactivado = false),
regalos AS (
  SELECT DISTINCT g.id_producto
  FROM fecego.vta_promocion_regalo g
  JOIN promo pr ON pr.id_promocion = g.id_promocion
  WHERE g.id_empresa = 1 AND g.baja = false),
codigos AS (
  SELECT DISTINCT c.id_producto, pr.clave AS promo_clave
  FROM fecego.vta_promocion_codigo c
  JOIN promo pr ON pr.id_promocion = c.id_promocion
  WHERE c.id_empresa = 1 AND c.baja = false)
SELECT lpad(c.id_producto::text, 6, '0') AS codigo,
       left(coalesce(p.nombre, '(no existe)'), 45) AS producto,
       c.promo_clave AS promocion,
       p.id_marca AS marca,
       coalesce((SELECT string_agg(DISTINCT ph.id_proveedor::text, ', ')
                 FROM fecego.com_proveedor_has_producto ph
                 WHERE ph.id_empresa = 1 AND ph.id_producto = c.id_producto
                   AND ph.baja = false AND ph.id_proveedor <> 0), '—') AS proveedores,
       CASE
         WHEN p.id_producto IS NULL THEN 'no existe en com_producto'
         WHEN p.baja THEN 'producto dado de baja en el ERP'
         WHEN NOT EXISTS (SELECT 1 FROM fecego.com_proveedor_has_producto ph
                          WHERE ph.id_empresa = 1 AND ph.id_producto = c.id_producto
                            AND ph.baja = false AND ph.id_proveedor <> 0)
           THEN 'sin proveedor vinculado, y su marca no participa'
         ELSE 'ni su marca ni sus proveedores estan dados de alta en la rueda'
       END AS causa
FROM codigos c
LEFT JOIN fecego.com_producto p
  ON p.id_empresa = 1 AND p.id_producto = c.id_producto
WHERE NOT (
  p.id_producto IS NOT NULL AND p.baja = false AND (
    p.id_producto = 999999
    OR p.id_producto IN (SELECT id_producto FROM regalos)
    OR p.id_marca IN (SELECT id_marca FROM marcas)
    OR EXISTS (SELECT 1 FROM fecego.com_proveedor_has_producto ph
               WHERE ph.id_empresa = 1 AND ph.id_producto = c.id_producto
                 AND ph.baja = false
                 AND ph.id_proveedor IN (SELECT id_proveedor FROM provs))))
ORDER BY causa, c.promo_clave, codigo;
```

**Cómo se lee.** Casi nunca es un problema de datos sino de **configuración de
la rueda**: hay una promoción `canal_venta = 'RUN'` apuntando a esta rueda,
pero el proveedor de esos productos no está dado de alta en
`cnf_rueda_negocios_proveedor`. Fue el caso de HI-TOOLS (`HTOO01`, proveedor
148) con 119 productos en testing el 2026-08-24, y de 186 el 2026-08-25.

**Cómo se arregla** — lo decide FECEGO, no la app:

- **Dar de alta el proveedor (o la marca) en la rueda** → los productos entran
  y la promoción funciona.
- **Desactivar esa promoción** para la rueda, si no debía participar.

Lo que **no** es opción: que el capturista teclee el descuento a mano. En la
rueda 3, **8,665 de los 9,981** productos en promoción lo tienen por encima de
su `descto_tope` (86.8%, medido el 2026-09-02 sobre el ERP de desarrollo). La
cifra se mueve con cada promoción que se configura — en agosto era 6,042 de
6,046 — así que conviene re-medirla antes de citarla.

## Clientes de la rueda: cuáles llegan y cuáles no

Replica `Export#clients`. Los clientes salen de `cnf_rueda_negocios_cliente`
unidos a `vta_cliente`, así que solo hay dos causas de omisión: que la clave no
exista en `vta_cliente`, o que esté de baja. La laptop no descarta ninguno más.

```sql
WITH r AS (SELECT 3::int AS id_rueda)
SELECT rc.clave_cliente AS clave,
       left(coalesce(nullif(cli.nombre_comercial,''),
                     concat_ws(' ', cli.nombre, cli.apellido_paterno, cli.apellido_materno),
                     '(sin nombre)'), 40) AS cliente,
       CASE
         WHEN cli.clave_cliente IS NULL THEN 'OMITIDO: no existe en vta_cliente'
         WHEN cli.baja THEN 'OMITIDO: cliente dado de baja'
         ELSE 'llega'
       END AS estado,
       cli.id_vendedor AS vendedor,
       CASE WHEN cli.id_vendedor IS NULL THEN NULL
            WHEN EXISTS (SELECT 1 FROM fecego.vta_vendedor v
                         WHERE v.id_empresa = 1 AND v.id_vendedor = cli.id_vendedor
                           AND v.baja = false) THEN 'ok' ELSE 'de baja' END AS vendedor_estado,
       (SELECT count(*) FROM fecego.vta_cliente_has_fiscales f
        WHERE f.id_empresa = 1 AND f.clave_cliente = rc.clave_cliente AND f.baja = false) AS fiscales,
       (SELECT count(*) FROM fecego.vta_cliente_has_remision x
        WHERE x.id_empresa = 1 AND x.clave_cliente = rc.clave_cliente AND x.baja = false) AS remision,
       (SELECT count(*) FROM fecego.vta_cliente_has_sucursal s
        WHERE s.id_empresa = 1 AND s.clave_cliente = rc.clave_cliente AND s.baja = false) AS sucursales
FROM fecego.cnf_rueda_negocios_cliente rc
LEFT JOIN fecego.vta_cliente cli
  ON cli.id_empresa = rc.id_empresa AND cli.clave_cliente = rc.clave_cliente
WHERE rc.id_empresa = 1 AND rc.id_rueda = (SELECT id_rueda FROM r) AND rc.baja = false
ORDER BY estado DESC, rc.clave_cliente;
```

**Las tres últimas columnas son las que valen para el evento**, porque un
cliente puede "llegar" y aun así ser inservible para cierto tipo de pedido:

| Columna | En 0 significa |
|---|---|
| `fiscales` | **no se le puede facturar**: no tiene RFC ni razón social. Si pide factura en el salón, el capturista se atora |
| `remision` | sí puede remisionar, va sin destinatario. La API solo exige el consecutivo cuando el cliente **sí** tiene perfiles |
| `sucursales` | el pedido queda sin dirección de entrega |

`vendedor_estado = 'de baja'` significa que el pedido viaja al ERP sin vendedor.

Solo lo accionable antes del evento — los que no pueden facturar:

```sql
SELECT rc.clave_cliente, cli.nombre_comercial
FROM fecego.cnf_rueda_negocios_cliente rc
JOIN fecego.vta_cliente cli
  ON cli.id_empresa = rc.id_empresa AND cli.clave_cliente = rc.clave_cliente AND cli.baja = false
WHERE rc.id_empresa = 1 AND rc.id_rueda = 3 AND rc.baja = false
  AND NOT EXISTS (SELECT 1 FROM fecego.vta_cliente_has_fiscales f
                  WHERE f.id_empresa = 1 AND f.clave_cliente = rc.clave_cliente AND f.baja = false)
ORDER BY 1;
```

## Qué se capturó fuera de catálogo (genérico 999999)

No es una consulta de omisión: es el insumo para decidir **qué productos
merecen darse de alta en el catálogo**. Lo que el capturista tecleó a mano
durante la rueda solo sobrevive en el ERP — la laptop lo pierde al cerrar la
rueda.

**La descripción y el número de parte viven en UNA sola columna.**
`vta_pedido_detalle.nombre_capturado` (varchar 40) los trae juntos separados
por espacio, porque así los manda la app (`OrderItem#erp_captured_name`). No
hay columna aparte, así que separarlos es **heurística, no dato**: se toma el
último token si trae algún dígito.

**Y la heurística solo funciona sobre lo que escribió esta app.** El "112 de
112" que decía antes esta línea era cierto pero **circular**: esas 112 partidas
son todas de `id_rueda = 3`, o sea las que nuestra propia app armó
concatenando descripción + número de parte, que es justo el patrón que la
heurística busca (10ª auditoría). Sobre las partidas del genérico **nativas del
ERP** —5 en la réplica, `id_rueda = 0`— **ninguna trae número de parte**, y la
única cuyo último token tiene dígito es `CODIGO 2810 CESPOL DE JULE P/LAVABO
20`, donde el 20 es parte de la descripción: ahí la heurística lo arrancaría.

En la práctica eso basta, porque el reporte existe para revisar lo que se
capturó **en la rueda**. Pero la columna "Número de parte" no es un dato del
ERP: es una lectura nuestra sobre un texto libre. La columna cruda es la fuente
de verdad y por eso la consulta la devuelve también.

```sql
SELECT ped.clave_pedido                                   AS "Clave pedido",
       ped.clave_cliente                                  AS "Clave cliente",
       det.id_producto                                    AS "ID fecego",
       CASE WHEN split_part(det.nombre_capturado, ' ',
                 array_length(string_to_array(det.nombre_capturado, ' '), 1)) ~ '[0-9]'
            THEN regexp_replace(det.nombre_capturado, '\s+\S+$', '')
            ELSE det.nombre_capturado
       END                                                AS "Descripción",
       CASE WHEN split_part(det.nombre_capturado, ' ',
                 array_length(string_to_array(det.nombre_capturado, ' '), 1)) ~ '[0-9]'
            THEN split_part(det.nombre_capturado, ' ',
                 array_length(string_to_array(det.nombre_capturado, ' '), 1))
       END                                                AS "Número de parte",
       det.nombre_capturado                               AS "Descripción + no. parte (crudo)",
       det.cantidad                                       AS "Cantidad",
       det.precio                                         AS "Precio unitario",
       det.total                                          AS "Total"
FROM fecego.vta_pedido ped
JOIN fecego.vta_pedido_detalle det
  ON  det.id_empresa    = ped.id_empresa
  AND det.clave_cliente = ped.clave_cliente
  AND det.fecha_pedido  = ped.fecha_pedido
  AND det.hora_pedido   = ped.hora_pedido
WHERE ped.id_empresa   = 1
  AND ped.id_rueda    <> 0        -- todas las ruedas; = 3 para una en particular
  AND det.id_producto  = 999999
  AND ped.baja = false
  AND det.baja = false
ORDER BY ped.clave_pedido, det.consecutivo;
```

El join va por la PK de negocio (`empresa + cliente + fecha + hora`), que es
como el ERP liga encabezado y detalle; `det.clave_pedido` existe pero no es la
llave.

Para sacarlo a CSV, la misma consulta dentro de un `\copy` (sin el punto y
coma final):

```bash
psql -h <host-erp> -U <usuario> -d <base> \
  -c "\copy (SELECT …) TO 'genericos-rueda.csv' WITH CSV HEADER"
```

Los dos `baja = false` excluyen lo cancelado. Para auditar **qué se capturó** y
no **qué quedó vivo**, quítalos y agrega `ped.baja` y `det.baja` a las
columnas.

## Lo negado de una marca: qué se pidió y qué se facturó

Lo que el proveedor quiere ver después de la rueda: de lo que sus clientes
pidieron, qué llegó y qué no. Vive entero en el ERP —la laptop no sabe nada de
facturación— y **cruza dos esquemas**.

> **Las tablas de CFDI son las de `fecego_cfdi`, NO las de `fecego`.** El
> esquema `fecego` tiene unas `fac_cfdi` / `fac_cfdi_detalle` homónimas que son
> para otro propósito y **están vacías**: una consulta que las use corre sin
> error y reporta que TODO se negó. Además los tipos difieren —en `fecego_cfdi`
> los flags son `boolean`, en `fecego` son `character(1)` con `'t'`/`'f'`—, así
> que copiar filtros de una a otra da `operator does not exist`.

**Antes de leer el resultado, la comprobación de cordura.** Si da 0, el reporte
va a listar todo como negado y será mentira:

```sql
SELECT count(*) AS renglones_cfdi, count(DISTINCT fd.clave_pedido) AS pedidos
FROM fecego_cfdi.fac_cfdi_detalle fd
JOIN fecego.vta_pedido ped
  ON ped.id_empresa = fd.id_empresa AND ped.clave_pedido = fd.clave_pedido
WHERE ped.id_rueda = 3;                    -- ← la rueda
```

Los dos parámetros del reporte son **`id_rueda`** y **`id_marca`**, ambos en la
CTE `solicitado`:

```sql
WITH facturado AS (
  SELECT fd.clave_pedido, fd.id_producto,
         sum(fd.cantidad) AS cantidad, sum(fd.total) AS monto
  FROM fecego_cfdi.fac_cfdi_detalle fd
  JOIN fecego_cfdi.fac_cfdi f
    ON f.id_empresa = fd.id_empresa AND f.id_cfdi = fd.id_cfdi
  WHERE fd.id_empresa = 1
    AND fd.baja = false AND f.baja = false AND f.cancelado = false
    AND f.pac_ok = true                    -- timbrada: sin timbre no hay factura
  GROUP BY 1, 2
),
solicitado AS (
  SELECT ped.clave_pedido, ped.clave_rueda, ped.clave_cliente, ped.id_vendedor, det.id_producto,
         sum(det.cantidad) AS cantidad, sum(det.total) AS monto
  FROM fecego.vta_pedido ped
  JOIN fecego.vta_pedido_detalle det
    ON  det.id_empresa = ped.id_empresa AND det.clave_cliente = ped.clave_cliente
    AND det.fecha_pedido = ped.fecha_pedido AND det.hora_pedido = ped.hora_pedido
  JOIN fecego.com_producto prod
    ON  prod.id_empresa = det.id_empresa AND prod.id_producto = det.id_producto
  WHERE ped.id_empresa = 1
    AND ped.id_rueda   = 3                 -- ← PARÁMETRO: la rueda
    AND prod.id_marca  = 22                -- ← PARÁMETRO: la marca (22 = HITOOLS)
    AND ped.baja = false AND det.baja = false AND det.cancelado = false
  GROUP BY 1,2,3,4,5
)
SELECT s.clave_cliente                                   AS "Clave cliente",
       s.id_vendedor                                     AS "ID vendedor",
       lpad(s.id_producto::text, 6, '0')                 AS "ID producto",
       prod.nombre                                       AS "Descripción",
       prod.modelo                                       AS "Modelo",
       prod.numero_parte                                 AS "Número de parte",
       trim_scale(s.cantidad)                            AS "Cantidad solicitada",
       trim_scale(COALESCE(f.cantidad, 0))               AS "Cantidad facturada",
       trim_scale(s.cantidad - COALESCE(f.cantidad, 0))  AS "Diferencia",
       CASE WHEN COALESCE(f.cantidad,0) > s.cantidad THEN 'Facturado de más'
            WHEN COALESCE(f.cantidad,0) > 0          THEN 'Negado parcial'
            ELSE                                          'Negado' END AS "Estado",
       round(s.monto, 2)                                 AS "Monto solicitado",
       round(COALESCE(f.monto, 0), 2)                    AS "Monto facturado",
       s.clave_pedido                                    AS "Folio ERP",
       s.clave_rueda                                     AS "Folio rueda"
FROM solicitado s
JOIN fecego.com_producto prod ON prod.id_empresa = 1 AND prod.id_producto = s.id_producto
LEFT JOIN facturado f ON f.clave_pedido = s.clave_pedido AND f.id_producto = s.id_producto
WHERE s.cantidad <> COALESCE(f.cantidad, 0)
ORDER BY (s.monto - COALESCE(f.monto, 0)) DESC, s.clave_cliente, s.id_producto;
```

**Por qué se agrupa por pedido + producto y no por partida.** Un mismo producto
puede venir en **varias partidas del mismo pedido** —28 casos en la rueda de
Oaxaca—, y el cruce por partida asigna lo facturado **entero a cada una**, así
que infla lo surtido y fabrica "facturado de más" que no existen (11 con el
cruce por partida, 9 reales).

**Lo que dice cada Estado:**

| Estado | Qué pasó |
|---|---|
| `Negado` | Se pidió y no se facturó nada. Incluye los pedidos que no llegaron a facturarse: **para el proveedor es lo mismo** —material que pidió y no llegó— y por decisión del usuario (2026-09-14) no se separan |
| `Negado parcial` | Se facturó menos de lo pedido |
| `Facturado de más` | Se facturó MÁS de lo pedido, así que la Diferencia sale **negativa** |

La `Diferencia` es `solicitada − facturada`: positiva es lo negado. El signo
solo no se lee bien en una hoja, y por eso va la columna `Estado` al lado.

**El "facturado de más" es real, no un artefacto del cruce**: comprobado un
caso con **una sola partida y una sola factura** (1,000 piezas pedidas, 1,040
facturadas), y esos productos no tienen empaque mínimo registrado que lo
explique. Es justo lo que el proveedor querrá revisar.

**Cómo saber si el cruce está sano:** los renglones que cuadran exacto. En
Oaxaca/HITOOLS fueron **925**, con $0.13 acumulados de diferencia por redondeo
sobre 1,021,763 pesos. Si esa cifra sale baja, el enlace `clave_pedido` +
`id_producto` no está funcionando y el reporte no sirve.

Para sacarlo a Excel, la misma consulta dentro de un `\copy` (sin el punto y
coma final):

```bash
psql -h <host-erp> -U <usuario> -d <base> \
  -c "\copy (SELECT …) TO 'negado-marca.csv' WITH CSV HEADER"
```

`trim_scale` está para eso: sin él las cantidades salen `6000.000000` y la hoja
se vuelve ilegible.

**Dos límites del reporte**, por si la pregunta que llega después es una de
estas: parte de **lo solicitado**, así que un producto de la marca que se haya
facturado sin estar en el pedido no aparece; y la columna `Folio rueda` sale
vacía en las ruedas anteriores a `clave_rueda` (2026-09-04).

## Un fallo de la API que no es de la app

Si un pedido se rechaza con *"Error interno del servidor; no se guardó nada"*,
el motivo real solo está en el log de `rueda-api`, **en el servidor**:

```bash
sudo journalctl -u fecego-rueda-api --since today | grep internal_error | tail -3
```

`Sequel::DatabaseDisconnectError` con *"terminating connection due to
administrator command"* significa que el Postgres del ERP se reinició o le
mataron las conexiones. No es el pedido ni la app: `OrderCreate.call` envuelve
todo en una transacción, así que no quedó nada a medias y basta volver a
transmitir (pasó el 2026-08-25).
