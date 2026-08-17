# Esquema ERP — catálogos de la rueda de negocios

Mapa del esquema del ERP de FECEGO (Postgres 16) para el **sync-down**: el
dataset de catálogos que `rueda-api` exporta y la app puebla en su Postgres
local antes del evento.

Descubierto por inspección de la BD viva (no de los repos Ruby). Todos los
joins y la integridad referencial se verificaron contra datos reales de un
respaldo con 3 ruedas cargadas (Veracruz / Chiapas / Oaxaca 2026).

## Conexión y convenciones

- Conexión de descubrimiento: `psql -p 1702 -d fecego` (Postgres.app local).
- Esquema: **`fecego`** (el otro es `fecego_cfdi`). `search_path` incluye ambos.
- **Filtrar SIEMPRE `id_empresa = 1`.** El ERP es multi-empresa y toda PK
  arranca con `id_empresa`.
- Patrón global de tablas: PK compuesta que inicia con `id_empresa`, bandera
  `baja boolean` (borrado lógico — filtrar `baja = false`), y auditoría
  `id_usuario_crea / fecha_crea / hora_crea` + `..._modifica`. Los
  `id_usuario_*` apuntan a `cnf_persona.id_persona`.

## Entidades base (catálogos)

### clientes → `fecego.vta_cliente`
- PK: `(id_empresa, clave_cliente)`. `clave_cliente varchar(6)` es el
  identificador de negocio; existe además `id_cliente int` (id numérico alterno).
- Campos: `nombre varchar(100)`, `nombre_comercial varchar(200)`,
  `apellido_paterno/materno`, `id_vendedor int` (FK → `vta_vendedor`),
  `linea_credito`, `dias_credito`, `id_sucursal`, `id_giro`, `id_canalventa`,
  `tipo_precio varchar(2)`, `aprobado bool`, `baja bool`.

### usuarios / login → `fecego.cnf_persona` + `fecego.cnf_persona_has_metodoidentifica`
- **Ojo con el nombre:** la tabla es `cnf_persona_has_metodoidentifica`
  (SIN guion bajo entre "metodo" e "identifica").
- `cnf_persona` PK `(id_empresa, id_persona)`: `nombre`, `apellido_paterno`,
  `apellido_materno`, `id_rol`, `rfc varchar(13)`, `curp`, `id_vendedor int`,
  `inactivo bool`, `baja bool`.
- `cnf_persona_has_metodoidentifica` PK `(id_empresa, id_persona,
  id_metodoidentifica)`: **credenciales** `username varchar(25)`,
  `password text`, `password_hash varchar(256)`. Catálogo de método:
  `cnf_metodo_identifica`.
- **Regla:** el login SIEMPRE se resuelve contra `cnf_persona` +
  `cnf_persona_has_metodoidentifica`, nunca contra `vta_vendedor`.

### vendedores → `fecego.vta_vendedor`
- PK `(id_empresa, id_vendedor)`. `nombre varchar(100)` (desnormalizado),
  `id_persona int` (FK → `cnf_persona`), `prefijo varchar(2)`,
  `id_coordinador_venta`, `id_coordinador_credito`, `baja bool`.
- La persona física vive en `cnf_persona` vía `id_persona`. Cuidado:
  a veces `id_persona = 0` (vendedor sin persona ligada).

### proveedores → `fecego.com_proveedor`
- PK `(id_empresa, id_proveedor)`. `clave varchar(6)` (código legible, ej.
  `ITWPOL`), `nombre varchar(100)`, `denominacion_comercial varchar(100)`,
  `tipo_persona varchar(1)`, `dias_credito`, `baja bool`.

### marcas → `fecego.com_marca`
- PK `(id_empresa, id_marca)`. `nombre varchar(50)`, `clave varchar(2)`,
  `baja bool`. (NO existe `cnf_marca`.)

### productos → `fecego.com_producto`
- PK `(id_empresa, id_producto)`. **El SKU/código oficial de FECEGO es
  `id_producto`** (entero, la PK). NO usar `com_producto_has_sku` como código
  oficial: esa tabla es el SKU del proveedor (su PK incluye `id_proveedor`).
- Campos: `id_marca int` (**FK directa** → `com_marca`), `nombre varchar(40)`,
  `nombre_publico varchar(50)`, `descripcion_corta varchar(300)`,
  `descripcion_larga text`, `modelo`, `numero_parte`,
  `id_unidadmedida int` (FK → `cnf_unidad_medida`),
  `id_categoria / id_subcategoria1 / id_subcategoria2`,
  `id_claveprodserv` (clave SAT), `existencia`, `clasificacion`, `baja bool`.
- **Precios:** `fecego.com_producto_has_precio`, PK `(id_empresa, id_producto,
  consecutivo)`. Columnas relevantes: `precio_lista`, `mayoreo_precio`,
  `publico_precio`, `intermedio_precio`, `internet_precio`, versiones
  `_con_iva` y `_redondeo`, precios de crédito (`cred_*`), `id_moneda`, `iva`,
  `igi`, factores de descuento `factor_descto1..5`. Filtrar `baja = false`.
  **El nivel que cobra la rueda es `cred_mayoreo_precio`** (decisión FECEGO
  2026-08-17); el export lo manda como `credit_wholesale_price` junto a
  público y mayoreo, que quedan de referencia. Un producto con crédito
  mayoreo en $0 queda invendible en la app (sin fallback a otro nivel).

## Relaciones producto ↔ marca ↔ proveedor

- **producto → marca:** columna directa `com_producto.id_marca`.
- **producto → proveedor:** tabla puente `com_proveedor_has_producto`
  PK `(id_empresa, id_proveedor, id_producto)` — relación N:M.
- **proveedor → marca:** tabla puente `com_proveedor_has_marca`
  PK `(id_empresa, id_proveedor, id_marca)`.

## Módulo rueda de negocios (nativo del ERP)

Existe como módulo del ERP (no es concepto nuevo). 6 tablas, todas con PK que
arranca `(id_empresa, id_rueda, …)`. Joins e integridad verificados con datos
(0 huérfanos).

| Tabla | PK | Rol / FKs |
|---|---|---|
| `cnf_rueda_negocios` | `(id_empresa, id_rueda)` | Cabecera del evento: `nombre varchar(50)`, `anio`, `fecha_inicio date`, `fecha_fin date`, `id_pais`, `consec_estado`, `consec_municipio`, `comentarios`, `baja`. |
| `cnf_rueda_negocios_proveedor` | `(…, id_proveedor)` | Proveedores participantes. `id_proveedor` → `com_proveedor`. |
| `cnf_rueda_negocios_marca` | `(…, id_marca)` | Marcas participantes. `id_marca` → `com_marca`. |
| `cnf_rueda_negocios_vendedor` | `(…, id_vendedor)` | Vendedores asignados. `id_vendedor` → `vta_vendedor` → `cnf_persona`. |
| `cnf_rueda_negocios_cliente` | `(…, id_vendedor, clave_cliente)` | Clientes registrados **con flujo de aprobación** ventas/crédito: `aprobado_ventas`, `aprobado_credito`, `id_usuario_aprueba_*`, `motivo_rechazo_credito`, crédito autorizado (`limite_credito_autorizado`, `saldo_facturas_autorizado`, `disponible_autorizado`, `por_facturar_autorizado`). `clave_cliente` → `vta_cliente`. |
| `cnf_rueda_negocios_persona` | `(…, id_persona, consecutivo)` | Personas de contacto/expositores por proveedor-marca. `id_persona` → `cnf_persona`, con `id_proveedor` e `id_marca` — ambos usan `0` como "ninguno": un renglón "solo proveedor" trae `id_marca = 0` y uno "solo marca" trae `id_proveedor = 0`. El export hace `NULLIF(…, 0)` a los dos y la membresía local acepta proveedor nulo (validando que venga al menos uno). |

## Precios especiales por rueda — resuelto sin tabla propia

(Resuelto 2026-08-17: la rueda vende al nivel **crédito mayoreo** del
catálogo general — no hay modelo de precio por rueda. Se conserva el
hallazgo original:)

**No existe** en el esquema del ERP una tabla de precio ligada a `id_rueda`.
Los precios provienen del catálogo general `com_producto_has_precio` (con sus
niveles mayoreo/público/intermedio/crédito y `factor_descto1..5`). Existen
además, fuera del módulo rueda y sin ligarse a `id_rueda`:
`vta_convenio_precio`, `vta_precio_mayoreo_pos_hist`, `com_precio_csv_hist`.

→ El "precio/beneficio especial por rueda" es **concepto a definir** en la app
nueva (modelo propio con FK a `id_rueda` + `id_producto`, o reúso del catálogo
general). Decisión diferida.

## Notas de integridad (verificadas con datos)

- `cnf_rueda_negocios_cliente` → `vta_cliente`: 0 huérfanos.
- `cnf_rueda_negocios_vendedor` → `vta_vendedor`: 0 huérfanos.
- Cadena `rueda_vendedor → vta_vendedor → cnf_persona`: OK.
- `cnf_rueda_negocios_persona`: las personas de contacto tienen ids altos
  (ej. 90092-90094, nombre "PROVEEDOR") ligadas a `com_proveedor`.

## Empaque mínimo de venta (`com_producto_has_empaque`) — investigado, NO es regla dura

Descubierto en la 2ª auditoría al evaluar cablear `min_sale_quantity`:

- La tabla `com_producto_has_empaque` guarda los empaques por producto:
  `cantidad` (piezas por empaque: 6, 10, 4, 12, 20…), `id_um`, código de
  barras, peso/volumen, y un boolean **`minimo`** que marca el empaque mínimo
  de venta. ~6,520 productos lo tienen (≈la mitad del catálogo), casi siempre
  un solo empaque con `minimo = true`.
- **Validado contra 1.8M de partidas reales de `vta_pedido_detalle`:** solo
  **~78–85%** de las cantidades vendidas son múltiplos exactos del empaque
  mínimo (consistente 2022–2026; ej. producto 82 con empaque 20 vendido en 2s
  y 5s). El ERP **no lo impone** como regla dura.
- **Decisión (usuario):** NO cablear la regla de múltiplos en la rueda; la
  columna local `products.min_sale_quantity` (que el sync nunca pobló) se
  **eliminó**. Si el tema del empaque revive, la fuente es esta tabla.
- **Revivió (2026-07-30, regla del usuario):** ahora SÍ es regla dura en la
  rueda. Export: CTE `emp` (MIN(cantidad) con minimo=true, ~957 productos en
  la rueda 3) → `min_sale_quantity` por producto → columna local en products
  (NULL = sin regla). La app valida que la cantidad sea múltiplo exacto
  (OrderItem#quantity_in_package_multiples), la partida nueva arranca en el
  empaque y las flechas ↑/↓ avanzan por empaque (data-step-size). Ojo: el
  ERP mismo no la impone (~78–85% de ventas reales son múltiplos) — aquí es
  más estricta que el ERP, a propósito.

## Catálogo de montos de división de facturas (`vta_pedido_monto_divide`)

Catálogo global (no ligado a `id_rueda`): PK `(id_empresa, consecutivo)`,
`monto NUMERIC(18,6)` y `observaciones`. 7 renglones reales: 0 (no dividir),
2,000, 5,000, 10,000, 15,000, 25,000 y 50,000 — coinciden con la distribución
de `vta_pedido.dividir_facturas`. Se exporta como `divide_amounts`
(consecutivo + monto con `trim_scale`) y alimenta la tabla local
`divide_amounts`: las opciones del combo "Dividir facturas cada ($)" del
paso 1. El pedido guarda el MONTO elegido, no una FK (igual que
`vta_pedido`).

## Universo de productos por capturista (2ª iteración de sync)

Regla del negocio (usuario, 2026-07-26): la asignación proveedor/marca del
capturista define su universo **duro** de productos vendibles en la rueda.

- **Fuente de la membresía:** `cnf_rueda_negocios_persona` — las columnas
  `id_proveedor` e `id_marca` que antes se ignoraban. `consecutivo` permite
  varias filas por persona (multi-proveedor/marca); `id_marca = 0` significa
  "sin marca" (se exporta como NULL). Viaja en la llave `people` del export →
  `business_round_people` local.
- **Hallazgo clave — relación real producto↔proveedor:** es
  `com_proveedor_has_producto`, NO los SKUs (`com_producto_has_sku`). Medido
  con MAKITA (proveedor 13): 2,207 productos vía `has_producto` y **0** vía
  SKUs; en toda la rueda 3: 10,839 vínculos vs 197 SKUs. El export manda
  `supplier_ids` por producto desde `has_producto`, y `ProductSupplier` local
  guarda la unión (con `supplier_sku` NULL cuando el vínculo no trae SKU).
- **Universo** = productos de TODOS sus proveedores (`ProductSupplier`) ∪ los
  de sus marcas (`products.brand_id`). Sin membresía → vacío (que el ERP no
  asigne proveedor/marca al capturista es problema operativo, no del sitio).

## Nota de índices (perf del export)

`com_proveedor_has_producto` (~58k filas) solo tiene el índice de su PK, que
**empieza por `id_proveedor`** — buscar por `id_producto` no usa índice. Por
eso los agregados por producto del export (supplier_ids/SKUs) se calculan en
CTEs con `GROUP BY` (un scan + hash join) y no con subqueries correlacionadas
(13k ejecuciones ≈ 28s). Aplica a cualquier query futura que recorra productos
consultando esta tabla.
