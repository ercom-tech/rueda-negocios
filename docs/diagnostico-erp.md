# Consultas de diagnóstico contra el ERP

Cuando el panel del servidor avisa de algo omitido, dice **cuántos** pero no
**cuáles**: el detalle vive en el ERP, no en la laptop. Aquí están las
consultas que lo responden, listas para pegar en `psql`.

> **Estas consultas replican los criterios de `rueda-api/app/queries/export.rb`.**
> Si el export cambia a quién deja entrar, hay que cambiarlas aquí también, o
> pasan a mentir sin que nada avise. Cada una dice de qué método sale.
>
> Todas usan `id_empresa = 1` y `id_rueda = 3`: ajusta la rueda.

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
rueda 3, 6,042 de los 6,046 productos en promoción lo tienen por encima de su
`descto_tope`.

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
