# Esquema del ERP — promociones

Lo que el ERP guarda de las promociones de la rueda y cómo se aplica. Medido
contra el ERP de desarrollo el 22 de agosto de 2026: 3,073 promociones en
total, de las cuales **38 son de la rueda** (`canal_venta = 'RUN'`), y
946,721 partidas de pedido con promoción en el histórico.

## Las cuatro tablas

```
vta_promocion                    cabecera: quién, cuándo, sobre qué universo
 ├── vta_promocion_codigo        el universo: QUÉ productos participan
 ├── vta_promocion_detalle       los escalones: CUÁNTO se descuenta
 │    └── vta_promocion_regalo   QUÉ se regala al alcanzar ESE escalón
```

PK de la cabecera `(id_empresa, id_promocion)`; código y detalle suman
`consecutivo`; el regalo suma `consec_detalle` **y** `consecutivo` — cuelga
de un escalón concreto, no de la promoción.

## Cabecera — `vta_promocion`

| Campo | Papel |
|---|---|
| `canal_venta` | `CDI` (2,334) · `POS` (701) · **`RUN` (38)** |
| `id_rueda_negocio` | Amarre con `vta_pedido.id_rueda`. Las 38 RUN son de la rueda 3 |
| `clave_criterio` | Cómo se armó el universo: `PRO` proveedor · `FAM` familia · `MAR` marca · `LIA` línea |
| `id_proveedor` / `id_familia` / `id_marca` | El valor del criterio; los demás en 0 |
| `vigencia_inicio` / `vigencia_fin` | En la rueda, del 15-ago al 15-sep 2026, con arranques escalonados (15, 16, 20, 21 y 22 de agosto) |
| `baja` / `desactivado` | Dos apagados distintos, y ninguno implica al otro |

**Trampa:** con `clave_criterio = 'FAM'`, `id_familia` apunta a
**`com_familia2`**, no a `com_familia`. Contra `com_producto_has_familia` el
match es 0 de 50; contra `com_producto_has_familia2`, 50 de 50.

## Universo — `vta_promocion_codigo`

La lista **explícita y autoritativa** de productos que participan. 6,227
renglones en la rueda (6,046 vivos).

El criterio de la cabecera es la memoria de cómo se armó la lista, **no una
regla a re-evaluar**: el ERP la deja curada. MAKITA participa con 2,134 de
los 2,209 productos de su proveedor; APEXTOOLS con 165 de 182. Re-derivar el
universo desde el criterio daría un conjunto distinto — y equivocado.

- `baja` por renglón: 181 códigos sacados de promociones **vivas** (EATON 45,
  ROTOPLAS 45, FAMA 37, MAKITA 34, TRAMONTINA HOGAR 19, TRAMONTINA DYNAMIC 1).
- `descto_porcentaje` por renglón es un **override que gana sobre el escalón**.
  Solo FANAL (3043) lo usa en la rueda: su único escalón va en 0% y sus 57
  códigos traen 10% o 20% propio. Es el segundo modo de promoción — descuento
  fijo por producto, sin escalera.
- **Ningún producto está en dos promociones RUN a la vez** (6,046 productos,
  máximo 1 promoción cada uno). Es dato del ERP y puede cambiar: el sync-down
  conserva la primera y reporta el resto en `shared_promotion_products`.

## Escalones — `vta_promocion_detalle`

Las 63 filas vivas de la rueda son `tipo_promocion = 'P'` y solo usan
`descto_porcentaje`: cero bonos, cero PPP, cero `regalos_permitir`, cero
`id_origenventa`.

`cond_tipo` — semántica confirmada por FECEGO el 2026-08-22:

| | Significa | Forma |
|---|---|---|
| `CE` | "en la compra de **entre** X y Y" | `[cond_cantidad_ini, cond_cantidad_fin]` |
| `CM` | "en la compra **mínima** de X" | `>= cond_cantidad_ini` (con `fin` en 0) |
| `PC` | "**por cada** X" | Multiplica, no escalona. No aparece en la rueda |

`cond_um` dice contra qué se mide el acumulado: **`MXN`** importe (38 filas),
**`PZA`** piezas (25 filas). *(La 64ª fila viva del conteo de arriba es la que
está dada de baja, con `cond_um` vacío.)* Ejemplos reales: MAKITA 30k:7% · 50k:10% ·
80k:12% · 200k+:14%. CUPRUM 5–14 pzas:7% · 15–24:9% · 25+:11%. Las 21
promociones de familia (IGOTO) son un solo escalón `CM PZA >= 1`: descuento
plano de 4% a 23% desde la primera pieza.

**Escalones traslapados:** FANDELI (3044) trae `>= 15,000 → 9%` y
`>= 20,000 → 9% + regalo`. El escalón que gana es el de **`cond_cantidad_ini`
más alto que se cumpla**; con "el primero que empata", un pedido de $25,000
se queda sin el regalo que el proveedor prometió.

## Cómo se elige el escalón

El acumulado es la **suma del importe bruto (cantidad × precio, antes de
descuento) de las partidas del pedido que pertenecen a esa promoción** — solo
esas, no el pedido completo.

Verificado en el pedido `RP0624`: de sus 19 partidas, 8 están en el universo
de la promoción 469 y suman **$17,466.43** → escalón 15,001–25,000 → **10%**,
que es exactamente lo que traen esas ocho. Las otras once llevan sus propias
promociones (463, 436) o ninguna.

Consecuencia: **el descuento es del grupo, no de la partida.** Un pedido
puede aplicar varias promociones entre sus partidas; una partida participa en
una sola.

## Cómo aterriza en el pedido — `vta_pedido_detalle`

| Campo | Contenido |
|---|---|
| `id_promocion` | Qué promoción aplicó (946,721 partidas) |
| `consec_promo` | Qué **escalón** de esa promoción |
| `promo_porcentaje` | El % que **dictó** la promoción |
| `descto_porcentaje` | El % **efectivamente aplicado** |
| `descto_monto` | El monto en pesos |
| `descto_tope` | Techo del descuento, copiado del producto (406,174 partidas) |
| `consec_origen_promo` | En una partida de **regalo**, el consecutivo de la que lo detonó |

Las cuatro columnas de promoción son **nullable con default 0**, y el ERP usa
**0 como "sin valor"** (sus 7.84M de partidas sin promoción lo llevan así; ya
hay 22,399 filas viejas con `consec_origen_promo` en NULL, así que NULL se
tolera pero no es la forma nativa). Por eso el payload manda 0 explícito: un
`nil` en un INSERT con lista de columnas escribe NULL, **no** el default.
`promo_porcentaje` y `descto_porcentaje` difieren en 20,631 partidas (2%).

`vta_pedido.promocode` (varchar 40) está vacío en las 1.26M de pedidos: no se
usa.

### El tope del producto NO topa a la promoción

`com_producto_has_precio.descto_tope` (lo que la app llama
`products.max_discount`) es la brida del descuento **manual**. De las 66,304
partidas históricas donde la promoción rebasaba el tope del producto, en
**66,300 ganó la promoción completa** (99.994%); los 4 restantes son regalos
que bajaron de 100% a 99% (3) y a 99.5% (1), todos con el tope en 9 — o sea
tampoco ganó el tope.

En la rueda el choque sería masivo. Los topes de los 6,046 productos en
promoción, **con el recorte que de verdad recibe la app** (el renglón de precio
vivo de menor consecutivo, que es el que el export copia a
`products.max_discount`):

| Tope | Productos |
|---|---|
| 5% | 3,752 |
| **0%** | **1,480** |
| 3% | 743 |
| 7% | 44 |
| 2% | 21 |
| 9% | 5 |
| 1% | 1 |

Contra descuentos de hasta 23%: **6,042 de los 6,046 (99.93%)** rebasan su tope
en el escalón que les toca, y 5,472 (90.5%) lo rebasan incluso en el más bajo.
Con el tope encima, casi ninguna promoción de la rueda se podría aplicar. Ojo
con los **1,480 productos que llegan con tope 0** (24%): en
`discount_within_limits` eso significa cero descuento manual, no "sin tope".

## Regalos — `vta_promocion_regalo`

Seis renglones en tres promociones de la rueda: FLEXIMATIC (2 exhibidores ×1,
en **ambos** escalones), FANDELI (1 esmeril SKIL, solo en el de $20,000), ITW
POLIMEX (8 soldaduras Devcon, en el de $8,000).

**El ERP no regala en $0 en SUS promociones.** Factura el regalo a precio de
lista con un descuento calculado para que el **total de la partida** quede en
**$0.25 + IVA = $0.29**, sin importar la cantidad: una fila de 6 piezas a
$32.83 lleva 99.87% y sale en $0.29, igual que una de 1 pieza. Sus 459
partidas de regalo llevan `promo_porcentaje = 100` sin una sola excepción — la
promoción dictó "se regala entero" y el aplicado es el 99.9x que deja los
centavos.

**La rueda no lo imita: sus regalos van con 100% de descuento y total $0.00**
(decisión FECEGO 2026-08-22). El ERP clava el centavo desde el *monto* del
descuento, mientras que la app lo deriva del *porcentaje* —que la columna
limita a dos decimales—, así que imitarlo daba un neto aproximado (entre $0.25
y ~$0.31 según el precio) y el papel del cliente terminaba cobrando centavos
por algo prometido regalado. Con 100% el regalo vale cero en pantalla, en el
PDF y en el ERP, y el total del pedido no arrastra centavos de nadie.

El 100% no es ajeno al ERP: ya tiene **729 partidas con `descto_porcentaje =
100` y total $0.00**, repartidas en 459 pedidos. Y su validación de montos es
por fórmula, así que descuento = subtotal, IVA = 0 y total = 0 cuadran solos.
El **precio de lista sí viaja**: el ERP guarda precio y descuento en columnas
distintas, y una partida en precio 0 no diría cuánto valía lo que se regaló.

**`regalos_permitir` y `regalos_todo` vienen en 0/false en las 38 promociones
RUN**, y FLEXIMATIC tiene dos productos de regalo en cada escalón.

Lo que dicen los datos, sobre los escalones del ERP **con al menos un regalo
configurado**: solo existen dos combinaciones — `(N≥1, true)` en 442 escalones
y `(0, false)` en 7. La forma "elige N" (`permitir > 0` con `todo = false`)
**no aparece en ninguna fila**, así que no se puede afirmar que el par exprese
esa semántica. Y más duro: de los regalos efectivamente emitidos en pedidos,
el **100%** salió de escalones `(N, true)`; con `(0, false)` el ERP **nunca ha
emitido un regalo**. Los 7 escalones así son 4 de esta rueda y 3 de CALIDRA
(canal POS), y el único con más de un regalo no tiene un solo pedido
histórico — el ERP tampoco resuelve el caso solo.

Por ahora se dan todos (decisión del usuario 2026-08-22) y queda en el backlog
preguntarle a FECEGO qué significa esa configuración.

## Detalles operativos

- **El ERP no impone el tope de 45 partidas.** Su máximo histórico real es
  **287**, y 3,294 pedidos pasan de 45. El 45 es regla de negocio de la rueda,
  y los regalos no cuentan contra él.
- **Un producto de regalo puede no pertenecer a la rueda.** El esmeril SKIL de
  FANDELI (26748) no está en ningún universo RUN ni es de una marca o
  proveedor participante: el export lo suma al catálogo a propósito, o la
  laptop no podría materializar la partida.
- **414 productos del catálogo de la rueda 3 tienen crédito mayoreo en $0** y
  son invendibles: 302 con renglón de precio en 0 y 112 sin renglón de precio
  vivo. *(El "102" que circulaba desde la 6ª auditoría no se reproduce con
  ningún recorte.)* Ninguno de ellos está en el universo de una promoción, así
  que no afectan a los descuentos ni a los regalos.
