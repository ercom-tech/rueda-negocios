# memory — rueda-negocios

**Bitácora de decisiones y su porqué.** Se consulta cuando hace falta entender
por qué algo está como está, o recuperar el contexto de un cambio viejo. Se
escribe en el paso **Documentar** del flujo PAIVD.

## Dónde va cada cosa

| Archivo | Contenido | ¿Se carga solo? |
|---|---|---|
| `CLAUDE.md` | Contrato del proyecto: forma de trabajo, arquitectura, stack | Sí |
| `docs/convenciones-visuales.md` | Normas de UI y de los textos al usuario | Sí (import) |
| `docs/convenciones-codigo.md` | Normas y trampas del stack | Sí (import) |
| **`memory.md`** | **Bitácora: decisiones y su porqué** | **No — se consulta** |
| `backlog.md` | Lo que falta implementar | No — se consulta |
| `docs/erp-esquema-*.md` | Esquema del ERP (catálogos y pedidos) | No — se consulta |
| `docs/instalacion-laptop.md` | Instalación en la laptop-servidor | No — se consulta |
| `docs/auditorias.md` | Cómo se audita: método y dimensiones | No — se consulta |
| `docs/auditorias-2026-07.md` | Historial de las 2 primeras auditorías (cerradas) | No — archivo |

Regla práctica: si es **norma que debe regir cada cambio**, va a las
convenciones (que sí se cargan). Si es **el porqué de una decisión**, va aquí.
Si es **algo por hacer**, va al backlog.

## Índice de la bitácora

- Decisiones generales del proyecto (abajo)
- 8ª, 7ª, 6ª, 5ª y 4ª auditorías — remediación
- Descubrimiento del esquema de catálogos (ERP)
- Fase A — scaffolding · Fase B — login, menú, reportes, pedido (arcos 1–3)
- Fase C — `rueda-api` export / sync-down
- Fase D — rake `sync:down`, sync-up, panel del servidor, estatus del pedido

## "Descartar" no descartaba (2026-08-26)

A petición del usuario se validó si el botón Descartar realmente descarta, por
los dos caminos: directo en el pedido y llegando desde el reporte de capturados
(el folio del reporte abre el mismo `orders#show`). **Los dos fallaban** cuando
el pedido tenía una promoción aplicada.

Es la **tercera puerta** del mismo candado que dos días antes rompió el
sync-down y "Cerrar rueda": el `before_destroy` con `throw :abort` de
`OrderItem`. `orders#destroy` llamaba a `order.destroy` sin mirar el resultado,
las partidas abortaban, el pedido sobrevivía y el flash decía "Pedido
descartado.".

**Lo grave es el caso del reporte.** Ahí el pedido está `captured`, así que
sobrevive y **el siguiente sync-up lo transmite al ERP**: una venta que el
capturista dio por cancelada acaba surtida, cobrada y entregada. En un borrador
solo se pierde la captura.

Se resolvió con `Order#discard!` (hermano de `purge_transmitted!`): borra
partidas y pedido con `delete_all`/`delete`. El candado queda intacto para el
bote de basura de una fila, que es a lo que apunta. Por decisión del usuario,
**descartar un capturado sigue permitido** (`editable?` solo excluye
transmitidos).

De paso se barrió el resto del código buscando el mismo patrón: los otros dos
`destroy` están bien — `order_items_controller` comprueba el resultado
(`unless item.destroy`) y `Promotions::Group` usa el bypass `promotion_managed`.

**Lo que enseña, y por lo que este renglón vale más que su arreglo:** es el
mismo defecto que la 6ª auditoría marcó ALTA —"el `destroy` cuyo resultado
nadie mira"— reapareciendo por una puerta nueva **dos auditorías después**, y
lo encontró una pregunta del usuario, no una auditoría. Cuando un candado nuevo
entra al sistema hay que ir a buscar a TODOS los que llaman a `destroy`, no
solo a la pantalla que lo motivó. Las tres roturas (sync-down, cerrar rueda,
descartar) salieron del mismo `throw :abort` y aparecieron de una en una, con
días de diferencia.

## El candado que impedía purgar (2026-08-25)

Con los pedidos del día ya transmitidos, "Obtener información" empezó a fallar
en la laptop. El panel decía *"No se pudo obtener la información. Revisa que el
servidor esté disponible"* y, debajo, *"La información no trajo ninguna
promoción: revisa que el servidor esté actualizado"*. Las dos pistas apuntaban
a la API, y las dos eran falsas.

**La causa, del log:**

```
PG::ForeignKeyViolation: update or delete on table "promotion_tiers"
violates constraint on table "order_items"
DETAIL: Key (id)=(92) is still referenced from table "order_items".
en down.rb:106 clear_catalog!
```

**Es el choque de dos remediaciones nuestras.** La 7ª auditoría le puso a
`OrderItem` un `before_destroy` con `throw :abort` para que una pestaña
rezagada no borrara por el endpoint una partida con promoción aplicada — un
candado dirigido al CAPTURISTA. Pero las dos purgas del SISTEMA (el replace del
sync-down y "Cerrar rueda") borran con `Order.transmitted.destroy_all`, y pasan
por el mismo callback: las partidas sobrevivían a la purga **sin excepción ni
aviso**, y el borrado del catálogo reventaba después contra sus llaves foráneas.

**"Cerrar rueda" fallaba peor: en silencio.** Ahí no hay catálogo que borrar
después, así que no reventaba nada — simplemente dejaba los pedidos vivos y
reportaba éxito. Es la operación con la que se cierra el evento.

**Arreglo:** `Order.purge_transmitted!`, usado por los dos servicios, borra con
`delete_all` (que no dispara callbacks) y borra las partidas **explícitamente
antes** que los pedidos, porque `delete_all` tampoco dispara
`dependent: :destroy`. El candado sigue intacto para la UI, y hay una prueba
que lo comprueba junto a las otras dos.

**Cuándo aparece:** el segundo día de un evento. Se transmite al final del día
1 y al día 2 se vuelve a obtener información. Ninguna auditoría lo cazó porque
el estado que lo dispara —pedidos transmitidos con promoción, todavía en la
laptop— solo existe después de un ciclo completo.

**Y un segundo defecto que salió de paso:** el aviso de "no trajo ninguna
promoción" se encendía también en corridas FALLIDAS, porque el summary viene
vacío y `nil.to_i.zero?` da true. O sea que el panel acusaba a la API de estar
desactualizada cuando el problema era local. Ahora exige `run&.completed?`. La
lección para los avisos del panel: **un contador en cero significa "corrió y
dio cero", no "no corrió"** — y en un camino de falla los dos se confunden.

## El panel que no se enteraba (2026-08-25)

En la laptop, una transmisión se quedaba "en progreso" para siempre; abrir el
panel en otra pestaña mostraba "Listo". O sea: el servidor tenía el estado
bueno y la pestaña vieja no se había enterado.

**Causa: el broadcast salió cuando nadie escuchaba.** Al lanzar el sync el
controlador responde `redirect_to root_path`; el navegador NAVEGA, y esa
navegación tira la suscripción de Action Cable mientras abre otra. La corrida
termina en menos de un segundo —con pocos pedidos es lo normal— y su broadcast
cae justo en ese hueco. Con el adaptador `async` no hay retención ni reenvío al
que llega tarde: el mensaje se pierde y la página conserva el HTML que se
renderizó con la corrida viva. Antes no se notaba porque los sync tardaban más.

**Arreglo:** el panel PIDE su estado además de esperarlo. `server#menu` devuelve
el mismo turbo_stream que emite el broadcast, y `sync_status_controller` sondea
cada 3 s **mientras hay corrida viva**. El broadcast se conserva como camino
rápido; el sondeo cubre cuando no llega, y de paso deja el panel a salvo de que
Action Cable falle por cualquier otra razón durante el evento.

**Dos trampas que costaron sangre y quedaron en las convenciones:**

1. **El sondeo tenía que ser condicional, no por eficiencia sino por
   corrección.** La respuesta reemplaza el div que lleva el `data-controller`,
   así que Stimulus lo reconecta: un refresh incondicional en `connect()` es un
   bucle infinito de peticiones contra la laptop que está sirviendo a todo el
   salón. La condición viene en el HTML nuevo, así la cadena se apaga sola.
2. **La primera versión de la prueba de sistema pasaba SIN el arreglo.**
   Asumí que en test los broadcasts no viajan; falso: el adaptador `test`
   hereda de `Async` y el servidor de Capybara vive en el mismo proceso, así
   que sí se entregan. Había que cerrar la corrida con `update_columns` —que
   salta el callback— para reproducir el mensaje perdido de verdad. **Lo cazó
   el fail-first, no la lectura del código.**

**Y una que corregí antes de commitear:** `sync_down&.running? || sync_up&.running?`
da **nil** cuando no hay corridas, y nil rinde como cadena vacía en el atributo
del value de Stimulus. La prueba de sistema lo detectó.

### Lo que enseñó el diagnóstico, que es lo más caro de este renglón

Antes de esto diagnostiqué DOS causas equivocadas y llegué a implementar una
—un corte por antigüedad en `recover_orphaned!`, con latido y pruebas— que el
usuario mandó revertir. Ninguna hipótesis era descabellada:

- *"El job murió y el pid no lo delata con `:async`"*: el hueco existe de
  verdad (ver backlog), pero **no era esto** — las cinco corridas estaban
  `completed` en menos de un segundo. La consulta que lo demostraba costaba
  una línea y la hice **después** de escribir el arreglo.
- *"Action Cable rechaza el WebSocket por el `Origin`"*: el log mostraba
  `Started GET "/cable" [WebSocket] for 127.0.0.1` — conectaba bien.

**La regla:** cuando un síntoma admite varias explicaciones, la consulta que
las separa va ANTES del arreglo, no después. Aquí eran dos comandos de lectura.
Es la misma lección que la 8ª auditoría dejó escrita para las cifras —declarar
el recorte antes de concluir— aplicada al diagnóstico en vivo.

## 8ª auditoría (2026-08-24) — remediación

Alcance: solo lo posterior a la 7ª (`2bcc943..HEAD`, 4 commits). 4 auditores en
vez de 8, por el tamaño. Resultado: 1 CRÍTICA · 5 ALTA · 7 MEDIA · 10 BAJA ·
1 degradado. Remediada al 100%.

**El PDF salía sin totales en el 2% de los pedidos, y llevaba siete auditorías
vivo.** `render_footer` abría su `bounding_box` sin `height`, así que heredaba
como alto lo que sobrara de la hoja; cerca de cada frontera de página el pie no
cabía y prawn-table lo repartía renglón por renglón, y cuando la tabla cuadraba
exacta con la hoja **no se escribía nada**: ni Subtotal, ni Descuento, ni IVA,
ni Total, ni el importe en letra. Cuatro hojas en blanco con folio, `render`
sin excepción, y el papel firmándose así. Barrido propio: **28 de 180
combinaciones** defectuosas antes del arreglo, 0 después.

Por qué sobrevivió tanto: las pruebas del PDF leían el texto extraído del
documento **juntando todas las páginas**, y así un pie repartido en cuatro
hojas se lee idéntico a uno bien puesto. La medición que sirve es por página.
La trampa completa quedó en `docs/convenciones-codigo.md` → "PDF (Prawn)".

**Lo nuevo no creó el defecto pero lo volvió mucho más probable.** El prefijo
"REGALO — " deja el 82% de los renglones a doble alto (contra 6.5% del catálogo
normal), y los regalos no cuentan contra `MAX_ITEMS`, así que el impreso puede
rebasar 45 renglones. De ahí la regla nueva del método: preguntar qué hace más
**frecuente** el código nuevo, no solo qué rompe.

**La mitad de un commit mío nunca funcionó.** El aviso "Se muestran las
primeras 50 coincidencias" del buscador de **cliente** se calculaba en una ivar
y el partial lo lee de los locals: no se pintó jamás, y ninguna prueba tocaba
esa ruta. El de producto, con el mismo texto, sí funcionaba — que es lo que lo
volvió invisible. Ahora los dos buscadores tienen prueba.

**El `role="listbox"` estaba en el contenedor, no en la lista.** Como el
partial entero se inyecta ahí con `innerHTML`, el aviso y los mensajes de
estado caían **dentro** del listbox, que solo admite `option`/`group`. El
comentario que yo había escrito afirmaba justo lo contrario ("va fuera del
`<ul>`: el contenedor es un listbox"), y era verdad la premisa y falsa la
conclusión. El role vive ahora en el `<ul>`, en los tres buscadores.

**Una regresión mía en la flama.** Al pasarla a coral, el ícono quedó blanco;
la píldora de fondo es un nodo condicional que desaparece de golpe, pero el
`transition-colors` seguía animando el color ~150 ms → **blanco sobre crema,
1.16:1**: la flama se borraba justo al cruzar un escalón. El cambio de estado
va ahora sin transición (instantáneo y sincrónico con el fondo); la transición
se conserva solo en `offered`, que no tiene fondo.

**El latido a 0.5 se queda, con su número anotado.** Medido: la píldora cae a
2.24:1 la mitad de cada ciclo, bajo el 3:1 que piden los elementos gráficos.
Es decisión del usuario tomada a sabiendas (2026-08-24) y está registrada en
`promotions_helper.rb` junto con la tabla de medidas y con la salida que no
tiene ese costo (píldora opaca + `ring` que late), por si algún día se quiere.

**Un ALTA se cayó en verificación: `vta_cliente.dividir_facturas`.** El auditor
proponía precargar el monto del cliente. Se degradó a BAJA porque su "99.4%"
salía de un proxy sin validar (tratar *factura vacía* como *no dividida*:
75.8% de precisión; el número real es 54.6%), porque **el ERP tampoco lo
prefilla** —la coincidencia cliente↔pedido va de 50.5% a 99.5% *según quién
captura*, y sobre el mismo cliente un capturista coincide 0% y otro 93.8%: eso
solo pasa si se teclea a mano—, y porque en 2.5 años los 1,007 pedidos del
escenario temido cancelan menos que el promedio y se pagan al 100%.

**Lo que más hallazgos produjo no fue el código: fueron mis propias cifras sin
recorte.** Un "19.84% de las facturas" que eran todos los comprobantes (notas
de crédito y pagos incluidos), un "9 de cada 10" que solo vale para las 1,000
palabras más frecuentes, dos tiempos en milisegundos irreproducibles, un
"2.31:1 en deuteranopía" sin superficie de referencia. Ninguno cambiaba una
decisión; todos costaron re-medirse. Ver la regla nueva en `docs/auditorias.md`.

## 6ª auditoría (2026-08-19) — remediación

Artifact: https://claude.ai/code/artifact/ef320711-a03f-4db0-a399-313f9089ff5b
(2 ALTA consolidados · 12 MEDIA · 30 BAJA · 1 degradado, con la 8ª dimensión
—Textos de los caminos de falla— estrenada y fija). Remediada completa en el
mismo ciclo. Aprendizajes que trascienden su arreglo:

- **Un formulario que vive en un panel desechable hereda su destructividad.**
  El mini-formulario del genérico se perdía por 4 rutas (clic fuera, tecla
  con foco fantasma, pausa, error de red). La regla que quedó: con captura a
  medias (`data-autocomplete-keep` + campos no vacíos), NINGUNA ruta
  implícita limpia el panel — solo el Cancelar explícito; el foco se da en
  `connect()` (el `autofocus` streameado perdía SIEMPRE contra el `reset()`
  del autocompletado, confirmado con clics reales).
- **El desenlace del pedido atorado quedó cerrado en sus tres tramos:** el
  `destroy` de un transmitido avisa en vez de confirmar un no-op; el 422 de
  colisión enuncia el paso que saca del bucle (DESCARTAR en la laptop —
  cancelar en el ERP no libera: las partidas del cancelado siguen vivas); y
  empatar contra un pedido cancelado (`find_existing` ahora trae `ped.baja`)
  es 422 con salida, no éxito idempotente. Las guardas ofrecen la
  alternativa de descartar.
- **El barrido de huérfanos corta por boot:** una corrida iniciada antes del
  boot actual tiene al dueño muerto por definición — cierra el pid reciclado
  por daemons de root (EPERM → "vivo"), el único caso donde reiniciar no
  curaba. Los jobs registran su pid en `perform`, verifican `running?` al
  arrancar y cierran con `finish_interrupted!` en `ensure` (las excepciones
  fuera de StandardError dejaban la corrida viva).
- **La idempotencia acepta ambas derivaciones del total** (written_total y
  el redondeo de la suma exacta de la API anterior): un pedido insertado por
  la versión vieja y reintentado con la nueva daba colisión falsa.
- **La ventana de despliegue se documentó con el orden INVERTIDO** (ERP
  migrado → API → laptop) tras verificar que "la API vieja ignora los campos"
  ahora significa perder la descripción del genérico en silencio y dejar el
  catálogo sin precio. La API desplegada real es `b43495a` (pre-4ª).
- Higiene menor que quedó de paso: control chars colapsados en la captura
  del genérico, precio del genérico a 2 decimales (el PDF imprime a 2 y el
  renglón no cuadraba), el PDF del genérico imprime lo MISMO que viaja al
  ERP (descripción + parte), receta única `item_field_form` para los 5
  forms de la fila, `with_env`/`login_as` compartidos, consulta de ruedas
  unificada en la API, y el usuario desactivado con contraseña correcta ya
  no lee "usuario o contraseña incorrectos".

## 7ª auditoría (2026-08-22) — remediación

Reporte: https://claude.ai/code/artifact/dbf4c8bc-85c8-437e-a9b0-2e3fa81db0af
Alcance: la funcionalidad de promociones (~1,900 líneas nuevas). **2 ALTA · 12
MEDIA · 21 BAJA · 1 refutado · 2 no alcanzables.**

### Lo que la pasada adversarial cambió

De nueve hallazgos graves: uno refutado, dos no alcanzables, cuatro degradados.
Y encontró por su cuenta el peor del ciclo. Vale la pena el detalle porque
enseña a leer los reportes:

- **REFUTADO — "la columna de promoción queda fuera de pantalla en tablet".**
  El desborde existe (40 px a 768) pero la página nunca desborda, el swipe
  táctil alcanza la flama, `overflow-x-auto` es preexistente, y —lo decisivo—
  **con la promoción aplicada la tabla se angosta y `maxScroll = 0`**: el
  estado que se describía como catastrófico es justo el que deja la flama a la
  vista.
- **NO ALCANZABLE — el override invertido y el regalo sin precio.** El primero
  porque en la rueda 3 override>0 y escalón>0 nunca coexisten; el segundo
  porque 0 de los 6,046 productos del universo tiene precio 0.
- **Tres cifras estaban mal por el RECORTE, no por la consulta**: 350 casos de
  override (eran 231, por pares duplicados y un join sin `consec_promo`),
  61,128 códigos (eran 6,046) y 102 productos en $0 (eran 414).

### Los dos ALTA: el modal contra el layout

Los dos salen de lo mismo — el modal de promoción es la primera capa flotante
que **carga su contenido después de abrirse**:

1. **El header se pintaba encima.** El diálogo es `z-50` pero vivía dentro de
   un wrapper `z-10`, hermano del header `z-20`. Un toque cerca del borde
   superior del modal caía en "Cerrar sesión". La regla de wrappers hermanos
   ya estaba escrita desde una auditoría anterior — y aun así se pisó, porque
   el caso nuevo (dos regiones hermanas, cada una con modal) no se parecía al
   viejo. **La salida no es dar z-20 a la otra: es que ninguna lleve z-index**
   y los diálogos compitan en el contexto raíz.
2. **El foco nunca entraba.** `focusables()[0]` corría con el placeholder, que
   no tiene ninguno. Tab paseaba por los controles de atrás: tres tabuladores
   y una tecla cambiaban la cantidad de una partida a ciegas. Lo que de verdad
   lo cierra es que **"Cerrar" viva en el cascarón** (hay un enfocable desde el
   primer instante); `focusInside` y el trap endurecido son redundancia.

### MEDIA remediadas

- **Borrar una partida congelada** no estaba bloqueado (`on: :update` no cubre
  `destroy`) y, peor, borrar PARTE del grupo no recalculaba el escalón: $140 de
  sobre-descuento rumbo al ERP. Ahora `before_destroy` con `throw :abort`.
- **El % que se anuncia** sale de `Group#percents_for`, no del escalón: con
  varios overrides dice "10% y 20% … según el producto".
- **`unapply!` sin `applied?`**: quitar dos veces borraba el descuento
  tecleado. Ahora devuelve false y el flash lo dice.
- **`belongs_to :order, touch: true`**: sin él, el detector de "editado durante
  la transmisión" era ciego a las promociones. Lo delataba la propia prueba,
  que escribía el `updated_at` del padre a mano.
- **N+1**: de 56 a 15 consultas por repintado (`Promotion.index_by_product`).
- **`blocked_reason`** pasó de una frase a tres ramas: con $14,999.48 recitaba
  que el mínimo eran $10,000, cinco mil por debajo de lo que ya llevaba.
- **Empaque mínimo**: no aplica a los regalos (la cantidad la dicta el ERP), y
  `apply!` va con rescate.
- **El buscador avisa antes del toque** cuando una promoción bloquea el
  producto, y **la fila congelada lleva badge** con el motivo.
- **El panel avisa** si la rueda quedó sin promociones, si faltaron productos
  de promoción y si alguno viene en dos.

### Documentación: cuatro afirmaciones falsas, tres mías de este ciclo

"Las columnas son NOT NULL" (son nullable, y el razonamiento encima era doble
falso), la semántica de `regalos_permitir` (la forma "elige N" no existe en
ningún dato), el desglose de topes (recorte equivocado; oculta que 1,480
productos llegan con tope 0) y los 102 productos en $0 (son 414, heredado de la
6ª y repetido como firme).

**La lección:** cualquier cifra que se escriba en `docs/` lleva su consulta al
lado, y toda medición declara su recorte — es la tercera auditoría seguida en
que el recorte, no la consulta, es lo que falla.

## Promociones de la rueda (2026-08-22)

Requerimiento: aplicar a los pedidos las promociones que el ERP configura para
la rueda (`vta_promocion` con `canal_venta = 'RUN'`). El esquema completo, con
las mediciones que lo respaldan, vive en `docs/erp-esquema-promociones.md`;
aquí van las decisiones y por qué se tomaron así.

### Lo que definió FECEGO

1. **Sugerido, no automático.** Cada fila cuyo producto está en promoción
   muestra una flama; el modal explica la promoción en formato de venta y
   ahí se aplica. Nada se aplica solo.
2. **La promoción pisa el descuento manual**, y al quitarla se devuelve el
   que el capturista tenía tecleado.
3. **Los regalos entran en esta vuelta** y pueden hacer que el pedido rebase
   las 45 partidas.
4. **Al aplicar, las partidas se congelan.** Para editarlas hay que quitar la
   promoción, corregir y volver a aplicarla si sigue calificando.
5. **Vigencia contra la fecha de captura del pedido.**
6. **Un pedido puede aplicar varias promociones; una partida, una sola.**

### Por qué el congelamiento simplificó todo

La propuesta inicial mantenía la promoción "viva": al cambiar cantidades, el
escalón subía o bajaba solo. El congelamiento que pidió el usuario elimina de
raíz el caso feo — un descuento que se evapora sin que nadie lo pidiera — y
deja una sola regla que explicar: *si quieres tocarla, quítala primero*.

De ahí salió el candado al **agregar**: un producto de una promoción ya
aplicada cambiaría el acumulado del grupo, pero las partidas están congeladas
y el descuento se quedaría calculado sobre una suma vieja. Se bloquea el alta
con el camino explícito, que es la misma frase que ya se usa para editar. Se
descartó "agregar y desaplicar sola": hace desaparecer descuentos que el
capturista no pidió quitar.

### El tope del producto NO topa a la promoción

Lo más contraintuitivo del cambio. `products.max_discount` (=
`com_producto_has_precio.descto_tope`) es la brida del descuento **manual**.
En el ERP, de 66,304 partidas donde la promoción rebasaba el tope, en 66,300
ganó la promoción. Y en la rueda los topes van de 3% a 9% contra descuentos de
hasta 23%: con el tope encima, **casi ninguna promoción se podría aplicar**.
`OrderItem#discount_within_limits` lo saltea cuando hay `promotion_id`.

### Decisiones de implementación

- **El universo (`promotion_products`) es autoritativo; el criterio no se
  re-evalúa.** El ERP ya deja la lista curada (MAKITA: 2,134 de 2,209
  productos de su proveedor). `clave_criterio`, `id_proveedor` e `id_familia`
  ni siquiera se bajan. Si algún día hicieran falta, ojo: con criterio `FAM`,
  `id_familia` apunta a `com_familia2`, no a `com_familia`.
- **El escalón se elige por `quantity_from` más alto que se cumpla**, no por
  consecutivo: FANDELI trae `≥15,000 → 9%` y `≥20,000 → 9% + regalo`
  traslapados, y con "el primero que empata" el pedido grande pierde el
  regalo.
- **`consec_origen_promo` se deriva al transmitir, no se guarda.** La
  renumeración del pedido mueve los consecutivos, y una referencia guardada
  apuntaría a la partida equivocada sin que nada lo delatara.
- **`manual_discount_percent` es memoria de la laptop y no viaja al ERP.** Hay
  una prueba que lo verifica sobre el cuerpo del POST: es la garantía de que
  restaurar el descuento previo no ensucia el pedido transmitido.
- **El export suma los productos de regalo al catálogo** aunque no sean de la
  rueda: el esmeril SKIL de FANDELI no está en ningún universo RUN, y sin eso
  el regalo era inmaterializable.
- **Un producto en dos promociones rompería "una partida, una promoción".**
  Hoy no pasa (los 6,046 están cada uno en una), pero es dato del ERP: el
  sync-down conserva la primera y reporta el resto en
  `shared_promotion_products`, en vez de dejar que la pantalla elija en
  silencio cuál descuento ofrece.

### El modal: dos trampas de Hotwire, en tensión

El diálogo vive dentro de `#order-detail`, que se repinta con morph. Eso pide
`data-turbo-permanent` — sin él, abrir el modal desde un campo con un cambio
pendiente lo cerraba solo (el clic dispara el blur, el blur el guardado, y el
repintado llega con el modal ya abierto). Pero `data-turbo-permanent`
**conserva el subárbol entero**, así que el contenido se congelaba: tras
aplicar, el modal seguía ofreciendo "Aplicar promoción" y el acumulado viejo.

La salida fue partirlo: **cascarón permanente + contenido en un turbo-frame
que el controller recarga en cada apertura** (`data-modal-refresh`). El
cascarón sobrevive al morph; el contenido siempre habla del pedido de ahora.
Y los formularios cierran el modal al terminar
(`turbo:submit-end->modal#close`): dejarlo abierto tapaba justo la tabla que
el capturista quiere revisar, y su fondo se comía el siguiente clic.

Los dos defectos los encontró la **prueba de sistema**, no la de integración
— ninguno es visible sin navegador.

`modal_controller` pasó a soportar varios diálogos por contenedor
(`data-modal-dialog-param`). Es lo que permite tener **un modal por
promoción** en vez de uno por fila: con 45 renglones de MAKITA serían 45
copias idénticas repintándose en cada tecla.

### El regalo va en cero, no en centavos

Primero se imitó al ERP, que factura sus regalos a precio de lista con un
descuento que deja el **total de la partida** en $0.25 + IVA = $0.29 (sus 459
partidas de regalo, con cualquier cantidad, y todas con `promo_porcentaje =
100`: dictó "entero", aplicó el 99.9x).

**No funcionó, y lo delató el PDF.** El ERP clava el centavo desde el *monto*
del descuento; la app lo deriva del *porcentaje*, que la columna limita a dos
decimales. El neto salía aproximado —entre $0.25 y ~$0.31 según el precio— y,
peor, **el papel del cliente cobraba centavos por algo que se le prometió
regalado**. Ponerlo en $0.00 solo en el PDF tampoco servía: los totales del
PDF se calculan de los mismos importes que imprime (para que cuadre con
calculadora), así que el papel habría dejado de coincidir con lo que factura
el ERP.

Decisión del usuario (2026-08-22): **100% de descuento**, cero de punta a
punta. No es ajeno al ERP —ya tiene 729 partidas con `descto_porcentaje = 100`
y total $0.00 en 459 pedidos— y su validación de montos es por fórmula, así
que descuento = subtotal, IVA = 0 y total = 0 cuadran solos. El precio de
lista sí viaja: precio y descuento son columnas distintas, y una partida en
precio 0 no diría cuánto valía lo regalado.

La lección general: **una diferencia de centavos deja de ser cosmética en
cuanto llega a un papel que ve el cliente.**

### Colores: el dorado no servía de trazo

La flama "disponible" tenía que ser la más llamativa, y el dorado sobre el
crema de la tabla da **1.56:1**: habría sido la más invisible. Va de
**superficie** —píldora dorada con el ícono en negro—, que además es el rol
que el manual le da al dorado. La flama aplicada es coral sólido (4.04:1,
cómodo sobre el 3:1 que pide AA para gráficos) y la que aún no alcanza es
`neutral-600`, el tono que la 4ª auditoría ya había validado sobre crema.

### Trampas que costaron una vuelta

- `Order#items_count_for_limit` pasó a excluir regalos. Hacerlo sobre la
  colección cargada rompió dos pruebas: se pregunta durante la validación de
  una partida que aún no existe, y la asociación en memoria ya trae la que se
  está construyendo. Va en SQL (`where(gift: false).count`).
- Una prueba del candado pasaba **por el camino equivocado**: el producto
  tenía `max_discount` bajo, así que quien rechazaba la escritura era
  `discount_within_limits` y no el candado. Se detectó con la comprobación de
  fail-first, no leyendo el código.
- Otra prueba de sistema "verificaba" que el modal sobrevive al morph
  haciendo focus/blur sin cambiar el valor — y `submitIfChanged` no envía
  nada, así que ningún morph ocurría. Pasaba con y sin `data-turbo-permanent`.

## Producto fuera de catálogo (2026-08-17) — genérico 999999

Requerimiento FECEGO: el proveedor puede vender productos que no están en el
catálogo usando el código **999999** ("AJUSTE DE MERCANCIA" en el ERP), con
descripción, no. de parte, cantidad, precio y descuento capturados a mano.
Decisiones del usuario: **es de todos** (sin membresía de proveedor/marca —
un capturista sin membresías captura solo con él), **descuento libre**
(0–100, ignora el `descto_tope`), y **tope duro de 40 caracteres** entre
descripción y parte.

- **El mecanismo es el nativo del ERP, medido:** sus propios pedidos con
  999999 llevan precio libre y el texto en
  `vta_pedido_detalle.nombre_capturado` (varchar 40) — vacío/NULL en 8.7M
  de partidas normales, lleno solo en las del genérico. No inventamos
  contrato: lo replicamos.
- **El tope de 40 es del ERP, no nuestro:** se valida en el modelo (con
  cuántos caracteres sobran), se anuncia en el mini-formulario, y la API lo
  rechaza con mensaje de negocio (truncar en silencio dejaría a surtido
  leyendo otra cosa que el papel del cliente).
- **UX sin JavaScript nuevo:** la opción del buscador ya hace POST, así que
  el primer POST del genérico responde el mini-formulario en el panel de
  resultados y el segundo crea la partida. La fila queda editable en
  descripción/parte/precio con el mismo patrón de la cantidad (guardar al
  salir, revertir si falla).
- **Candados:** los tres campos solo se aceptan en partidas del genérico
  (`item_params_for` / `generic_overrides`) — en el resto son snapshot del
  ERP y un PATCH forjado no los toca. El aviso de duplicado se apaga para el
  genérico (varias partidas fuera de catálogo son el uso normal), y
  `nombre_capturado` entra a la llave de idempotencia (editar el texto es
  contenido distinto).
- De pasada se corrigió un desfase del cambio de precio: el panel de
  sugerencias seguía mostrando el precio público; ahora muestra el crédito
  mayoreo (el que se cobra).

## Precio de la rueda (2026-08-17) — crédito mayoreo

**La rueda vende al precio crédito mayoreo** (decisión del usuario;
`com_producto_has_precio.cred_mayoreo_precio`). Cierra el renglón "precios
especiales de la rueda" del backlog: no hay modelo propio por rueda — se
cobra un nivel del catálogo general del ERP.

- Cadena: export (`credit_wholesale_price`) → `prices.credit_wholesale_price`
  local → snapshot de la partida (`Product#to_order_item_attributes`).
  Público y mayoreo siguen viajando de referencia.
- **Sin fallback:** un crédito mayoreo en $0 (6.5% del catálogo al decidirlo:
  3,656 de 55,949) deja el producto invendible con el aviso de "producto sin
  precio" — el dato se corrige en el ERP, que es su dueño. Decisión explícita
  del usuario entre las tres opciones.
- Contexto medido: crédito mayoreo ≈ mayoreo × 1.05 y ≈ 88% del público;
  nunca por debajo del mayoreo. `tipo_precio = 'MA'` del encabezado queda
  consistente (es la modalidad a crédito del mayoreo, y el campo es
  declarativo — 5ª auditoría).
- Los pedidos capturados ANTES del cambio conservan su snapshot al precio
  público: el snapshot es inmutable por diseño.

## 5ª auditoría (2026-08-12) — remediación

Artifact: https://claude.ai/code/artifact/a354356c-0f4b-4ce8-a62e-06656c5ba144
(1 ALTA · 13 MEDIA · 43 BAJA tras verificación · 1 retirado). Remediada el
mismo día en 10 bloques: el ALTA, las 13 MEDIA y 39 BAJA; 4 BAJA diferidas a
conciencia con registro en backlog (fiscales de factura en la API y CSP →
strengthening; `sucursal=0` → definir con FECEGO; kebab vs snake en URLs).
Suites al cierre: app **246** + 7 de sistema, API **51**. Una migración
(`sync_runs.pid`).

**El ALTA (duplicado en el ERP guiado por el propio 422)** se rompió en sus
tres eslabones: los motivos de falla posteriores al envío advierten "el pedido
pudo haber entrado al ERP: vuelve a transmitir sin editar"; el 422 de colisión
enuncia el camino completo (comparar contra el ERP, cancelar allá si es el
mismo, recapturar después); y la idempotencia compara las **partidas**
(producto, cantidad, precio, descuento), no solo total±1¢ y conteo — el
intercambio de productos del mismo precio ya no pasa como reintento legítimo.

**Aprendizajes que valen más que su arreglo:**

- **La invariante del redondeo del ERP es composicional:** encabezado = suma
  de las columnas de sus partidas *tal como quedaron guardadas* (total de
  partida redondeado a 2; descuento e IVA con precisión completa). Nuestro
  `round(Σ exacta)` divergía en ~47% de los pedidos. Y al cambiar el esquema
  de escritura, **la comparación de idempotencia tiene que derivar igual**
  (`written_total`), o el reintento legítimo colisiona — con 45 partidas la
  brecha llega a ~22 centavos, 22× la tolerancia. Bono: el PDF (suma de
  renglones redondeados) ahora cuadra centavo a centavo con la factura.
- **`insert_all` trae `ON CONFLICT DO NOTHING`:** un duplicado en el export
  se descarta en silencio, no revienta. Para probar la atomicidad del replace
  hubo que corromper con NOT NULL, no con duplicados.
- **El barrido de huérfanos ahora es seguro por `pid`, no por contexto:**
  cada corrida registra a su proceso dueño y solo se barre lo muerto. Eso
  permitió correrlo también al cargar el menú del servidor (autorrecuperación
  sin reiniciar) y eliminó la dependencia del adapter de jobs — la trampa
  documentada de Solid Queue en producción desapareció. El `ensure` del rake
  cierra la corrida ante Ctrl-C/kill (`Interrupt` no es `StandardError`: los
  `rescue` no lo tocan, el `ensure` sí).
- **La pausa de sync responde 422, no 200:** con 200, Turbo reportaba éxito y
  la palomita "Guardado ✓" salía junto al aviso de reintento — confirmado con
  clics reales. El controller además revierte los campos al valor guardado en
  cualquier envío fallido (`revertRemembered`), matando el "valor fantasma".
- **Los avisos del panel viven FUERA de las ramas de estatus:** el bloque de
  conflictos solo se pintaba en `completed` y una corrida parcial se lo
  tragaba. Regla: un aviso que reporta daño se pinta termine como termine la
  corrida.
- **Un conteo que mezcla causas produce diagnósticos equivocados:** la
  membresía de un capturista omitido por credencial caía en "sin proveedor ni
  marca" y mandaba a corregir lo que no estaba roto. Cada causa, su aviso.
- **`consider_all_requests_local = false` es gratis en esta app:** Rails
  sigue mostrando la página de depuración a `request.local?` (el navegador de
  la laptop), y la LAN ve las páginas de error en español.
- **Flechas con paso decimal: aritmética en unidades enteras del paso** y
  redondeo a sus decimales — la división flotante (0.3/0.1 = 2.9999…) atoraba
  la flecha o dejaba `0.30000000000000004` visible.
- **El 404 con mensaje de negocio necesita los dos lados:** la API responde
  `{error, message}` y `ApiClient#get` extrae el `message` — sin eso el
  operador leía "HTTP 404" y se iba a revisar la red por un typo de RUEDA_ID.

## 4ª auditoría (2026-08-11) — remediación

Artifact: https://claude.ai/code/artifact/2e76bab0-c6ae-4a0a-b219-9999f7e6dda2
(1 ALTA · 37 MEDIA · 31 BAJA · 0 vulnerabilidades). Primera con **7
dimensiones**: se estrenaron *Fidelidad con el ERP* y *Operación y
recuperación*, y produjeron el único ALTA y buena parte de las medias caras —
justo lo que predecía su justificación.

**Lo que enseñó la pasada de verificación.** De los 6 hallazgos que llegaron
marcados ALTA, **5 bajaron a MEDIA y 1 se refutó**. El refutado es el aviso
más útil: alegaba que el folio se rellena a `6 − len(prefijo)`, tomando la
regla de la rama de **sucursal** del ERP (1 carácter + 5 dígitos, contador en
`cnf_sucursal.venta_consec`). Nuestros pedidos entran por `id_sucursal_crea =
1` (matriz), que usa la rama de **persona**: 514,660 folios de 2+4, sin una
sola excepción. Medir la invariante en el recorte equivocado da una certeza
falsa con evidencia de aspecto sólido.

### A1 — Las remisiones llegaban al ERP sin destinatario (cerrado)

El capturista elige en el paso 1 a nombre de quién va la remisión y ese dato
**se quedaba en la laptop**: no estaba en el payload. En el ERP el pedido caía
con `consec_remision = 0` y sin datos en línea, combinación que el ERP nunca
ha producido — sus 383,881 remisiones desde 2024 se reparten en dos cuadrantes
(ticket de mostrador con datos en línea, flujo de pedido con puntero al
perfil) y el cuadrante "ninguno de los dos" tiene **cero filas**. De ese
puntero cuelga la cuenta referenciada de cobranza (`vta_remision_has_cuenta`)
y `fac_cfdi` copia esas columnas al timbrar en vez de re-resolverlas.

Cuatro piezas:

1. **`Order#clear_inactive_header_branch`** (`before_validation`). El paso 1
   pinta los campos de factura y los de remisión en el mismo formulario y solo
   oculta con CSS la rama que no aplica, **así que se envían igual**: una
   remisión podía llegar con el RFC real del cliente (peor que el nulo — 0 de
   212,860 remisiones lo llevan) y una factura con perfil de remisión. Ya
   estaba pasando: había facturas guardadas con `client_receipt_profile_id`.
2. **`Sync::Up` transmite `consec_remision`**, atado a `order.remission?` y no
   solo al dato guardado: las facturas lo llevan en 0 (243,318 de 243,334) y
   los pedidos capturados antes de esta remediación traen el valor rancio. Sin
   ese candado, la primera prueba contra un pedido real de la BD de desarrollo
   transmitía `consec_remision: 1` en una factura.
3. **`OrderCreate::REMISSION_DEFAULTS`** — RFC genérico `XAXX010101000` y uso
   `S01`, **impuestos** (no tomados del payload): si la app dejara escapar el
   RFC del cliente en una remisión, la API lo corrige. Defensa en profundidad
   sobre el punto 1.
4. **Guarda en `rueda-api`:** una remisión sin destinatario se rechaza **solo
   si el cliente sí tiene perfiles** en el ERP. Hay clientes sin ninguno (20 de
   los 47 de la rueda 3) y no podemos inventarles uno; lo que se rechaza es
   que el dato exista y no lo mandemos. Un consecutivo que no es de ese cliente
   también se rechaza.

**`dividir_facturas` entró a la limpieza por una razón distinta —y la decisión
se revirtió el 2026-08-24.** Está en el mismo bloque oculto del paso 1, así que
una remisión que empezó como factura conservaba el monto sin que nadie pudiera
verlo ni corregirlo. Se resolvió limpiarlo (2026-08-11): una remisión viajaba
siempre en 0, "coherente con la pantalla que ya lo rotula como campo de
factura".

**Estaba mal, y el dato para verlo ya estaba escrito aquí.** El usuario lo
corrigió: el monto de división aplica también a las remisiones. Hoy el campo se
muestra en los dos tipos, viaja tal cual al ERP y se imprime en el PDF.

Lo que enseña este renglón no es "hay que re-medir con mejor recorte". El
"3,079 de 110,577" era **correcto para su recorte** (remisiones del flujo de
pedido desde 2024: 2.78%, contra 2.84% del universo completo de 6,128 de
216,100) y **ya apuntaba a la conclusión buena** — decía textualmente que el
ERP sí acepta remisiones con monto. Lo que falló fue la **inferencia** que se
puso encima: se leyó "es la moda de las facturas" y se concluyó "entonces en
remisión va en 0", cuando el propio dato decía que era regla de negocio viva.

**La lección: una cifra correcta no protege de una conclusión equivocada.**
Registrar esto como "falló el recorte" —que fue el primer diagnóstico— manda a
la siguiente auditoría a re-medir, que es justo lo que no hacía falta (8ª
auditoría). Se conserva la otra mitad, que sigue valiendo: **la invariante del
ERP obliga; su moda solo sugiere.**

**S01 vs P01: lo decidió el catálogo, no una preferencia.** El reporte proponía
P01 por ser la moda global (60%), pero `sat_uso_cfdi` lo tiene con `baja = t`:
está **retirado**. S01 "SIN EFECTOS LEGALES" es el vigente. La lección se
repite: antes de copiar la moda del histórico, revisar si el catálogo sigue
aceptando ese valor — la moda incluye décadas de datos con reglas viejas.

### Los tres huecos de la transmisión (cerrados)

Las tres MEDIA de fidelidad con el ERP, todas en `rueda-api`:

1. **Coherencia interna de la partida.** Se comprobaba el encabezado contra la
   suma de las partidas, pero no cada partida contra su propia cantidad y
   precio: con `cantidad: 1000` y `total: 116` el encabezado cuadra con la suma
   y almacén surte mil piezas contra un pedido de $116. `validate_item_amounts!`
   recalcula los cuatro importes con el orden de operaciones de `OrderItem`.
   **Verificado que no rechaza de más:** un pedido real de 45 partidas con
   cantidades, precios y descuentos deliberadamente feos da delta **0.0 exacto**
   en los 180 importes. El riesgo de una validación así es el falso rechazo en
   medio del evento, y esa medición es la que lo descarta.
2. **`total` a 2 decimales.** El ERP redondea `total` y **solo** `total`
   (`subtotal`, `descto_monto` e `iva_monto` conservan más decimales en 1.16M
   de cabeceras). Se redondea **al escribir**, no en la app: si se redondeara
   antes, el encabezado dejaría de cuadrar con la suma de sus partidas —hasta
   0.22 con 45 renglones— y la propia validación del punto 1 lo rechazaría.
   Además así el PDF, el reporte y la pantalla no cambian.
3. **Ocho columnas en NULL.** `BLANK_DEFAULTS`. La auditoría las llamó "las
   ocho columnas sin DEFAULT que no ponemos": son **53** las que no tienen
   default. El criterio correcto no es la ausencia de default sino **cuáles el
   ERP nunca deja en NULL**, y medido así son exactamente esas ocho (0 nulos en
   414,529 pedidos); las otras 45 sí admiten NULL y se dejan como están.

Lo que enseñan juntas: **medir la invariante, no la forma de la tabla.** Dos de
los tres criterios que traía el reporte estaban enunciados sobre el recorte
equivocado, y en ambos casos los números correctos se parecían lo bastante a
los del reporte como para no notarlo sin volver a consultar.

### Favicon propio y fuera el andamiaje PWA (2026-08-11)

El favicon era el de Rails: un círculo rojo. Se dibujaron tres opciones del
sector ferretero y **el criterio que decidió no fue el gusto sino el tamaño**:
un favicon se juzga a 16 px, no a 256.

- **Silueta sólida, no el ícono del sitio en chiquito.** La iconografía es
  Heroicons outline a trazo 1.5, que a 16 px simplemente desaparece.
- **Ganó la tuerca hexagonal** porque son dos figuras geométricas y nada más:
  a 16 px sigue reconociéndose. La llave española, que era mi recomendación
  inicial, se convierte en una diagonal oscura — se distingue, pero ya no se
  sabe qué es.
- **Negro sobre dorado, no al revés.** La objeción de "parece ajustes" no venía
  de la tuerca sino de la figura clara sobre fondo oscuro, que es como se ven
  los íconos de configuración. Invertida deja de leerse así, y el dorado de
  FONDO conserva lo que importa en una laptop con varias pestañas abiertas:
  **el color identifica antes que la forma**.

**Borrado `app/views/pwa/`** (manifest + service worker) y las dos líneas
comentadas que lo enlazarían: sin rutas, sin enlace y sin razón de ser — el
offline aquí se resuelve a nivel de red, no con una PWA instalable. Mismo
criterio que el partial `orders/_field`: **el andamiaje sin usar es lo que
después confunde**, porque quien lo encuentra asume que la capacidad existe.

### El bloque visual, cerrado (BAJA)

Seis desviaciones de las convenciones visuales. Cinco eran cosméticas; una
tenía consecuencia y fue la que más enseñó.

**El aviso del tope de partidas estaba en 2.21:1.** Al llegar a 45, el
placeholder deja de ser una invitación a escribir y pasa a ser el mensaje que
explica por qué no se puede — pero vivía dentro del bloque atenuado al 60%.
Medí las salidas antes de elegir: `neutral-700` al 60% da 2.21, y **ni siquiera
`neutral-900` alcanza (3.25)**. O sea que el arreglo no era oscurecer el texto
sino **no atenuarlo**: el 60% quedó solo en el ícono, que es el control. Es la
regla que el propio archivo ya enunciaba para el contador y que no se había
aplicado al mensaje.

Las otras cinco: los tres chevrons a trazo 2 y el spinner de dos capas con
trazo 4 y relleno pasan a Heroicons outline a 1.5 (`arrow-path` girando), y el
`&times;` tipográfico del flash a `x-mark` — los 21 SVG del proyecto quedan al
mismo peso; el hover del hub de reportes baja de 1.03 a 1.015 como las otras
ocho cards; el textarea de observaciones pasa a blanco, que es la señal de
"esto se escribe" (en crema se veía idéntico al bloque de solo lectura de al
lado, mismo color, radio y borde); y el `bg-black/5` —único translúcido usado
como superficie de contenido— pasa a crema con borde, como los otros dos avisos
de esa misma card.

### El idioma del código, cerrado (BAJA)

Los ~35 identificadores en español que sobrevivían: los helpers de concordancia
de `Sync::Guards`, `productos`/`universo`/`mismo_sitio`, todos los locales del
importe en letra del PDF, `EN_PROCESO`, `DIAS`/`MESES` del calendario y una
docena en pruebas.

**En `rueda-api` NO se renombró nada, y eso también es la regla.** Ahí
`EMPRESA`, `prefijo`, `clave`, `id_rueda` y los alias de las CTE (`marcas`,
`provs`) espejan el ERP a propósito: traducirlos dejaría el SQL mitad y mitad,
que es peor que cualquiera de los dos idiomas completo. Quedó registrado como
excepción junto con `dividir_facturas` y el rol `capturista`, y con la
advertencia de que **las llaves del payload son el contrato de red**: un
renombre "por consistencia" ahí rompe el sync-up y el síntoma es un 422 en
pleno cierre de evento.

**La trampa volvió a morder, en una variante nueva.** La convención ya avisaba
de revisar el diff palabra por palabra, y yo protegí el texto entre comillas…
pero el texto visible también vive dentro de **literales de expresión regular**:
`assert_match(/Hay 1 pedido en borrador/, …)` se convirtió en "en draft" y solo
lo cazaron tres pruebas al fallar. La comprobación que sí sirve —listar todo el
texto en español que toca el diff, cadenas **y** regexes, y leerlo— quedó
escrita en las convenciones.

### `fecha_crea` = la captura, no la transmisión (decisión de FECEGO)

Era la única BAJA que dependía de una definición de negocio, y el usuario la
resolvió (2026-08-11): **"la fecha_crea debe ser la real cuando se capturó"**.
Antes registraba el momento del sync-up, así que una rueda del viernes
transmitida el lunes dejaba todos sus pedidos creados en lunes — y el ERP tiene
un índice dedicado por `fecha_crea`, o sea que cualquier corte de captura por
día los agrupaba en el día de oficina.

**Lo que la medición aportó a la decisión.** En el ERP `fecha_crea =
fecha_pedido` en el 99.69%, pero `hora_crea = hora_pedido` solo en el **5%**: en
sus pedidos nativos de rueda, `hora_crea` es idéntica a `hora_transmision`,
porque ellos transmiten el mismo día y ahí "crear" y "transmitir" coinciden. Su
patrón simplemente no cubre nuestro caso. Llevar solo la fecha habría dado un
sello incoherente —viernes con el reloj del lunes—, así que las dos van del
mismo instante. Vale la pena conservarlo: **cuando el histórico no cubre tu
caso, copiar su moda produce un dato peor que decidir con criterio.**

`TIME_TO_SECOND` desapareció: la hora de captura ya llega como `"HH:MM:SS"` en
el payload, así que la regla de "sin micros" se cumple sola.

### Las dos últimas de usabilidad (cerradas)

**Producto repetido sin aviso.** Agregar dos veces el mismo producto creaba dos
partidas idénticas y la sugerencia se veía igual que la de uno nuevo: con la
tabla scrolleando y 45 renglones posibles, el duplicado no se notaba y el ERP
surtía doble. **No se bloquea** —el mismo producto con distinto descuento es
legítimo, y el hallazgo era la ausencia del aviso, no la posibilidad—: se marca
en el buscador ("Ya está en el pedido, partida 3", y el botón pasa a "Agregar
otra vez") y el controlador lo repite al agregarlo, porque la lista se cierra
al elegir y el aviso previo ya no está a la vista. El modal de quitar nombra
ahora la partida: con el producto repetido, la descripción sola no decía cuál.

**Los anillos rojos no se apagaban al corregir.** Tras un submit inválido el
capturista elegía el valor que faltaba y veía todo igual de rojo, dudaba si
había guardado y volvía a abrir el combo a verificar. `select#choose` ahora
apaga su propio anillo y esconde el banner cuando ya no queda ninguno marcado.

Lo interesante fue el caso que **duplicaba** el defecto: elegir la razón social
auto-llena el uso de CFDI (`cfdi-default`), así que quedaban DOS campos llenos
y los dos seguían marcados. Se resuelve solo porque `cfdi-default` hace click
en la opción del otro combo, o sea que pasa por el mismo `choose`. La prueba de
sistema lo fija, y para escribirla hubo que darle a la razón social un uso de
CFDI por omisión — sin eso la prueba pasaba por el camino equivocado, con el
CFDI legítimamente pendiente.

### Deuda de convenciones (cerrada)

Cuatro MEDIA que no producían un defecto hoy pero cuyo costo **crece**: cada
una es una trampa para el siguiente cambio.

- **`Sync::Up` reimplementaba la capa HTTP** en vez de usar `ApiClient`: dos
  `Net::HTTP`, dos normalizaciones de URL, dos redacciones del mismo error.
  Tenía fecha de cobro: el día que entren los tokens y el TLS de la fase de
  strengthening, quien los agregue a `ApiClient` habría dejado el **sync-up**
  —la ruta de escritura al ERP, la de mayor riesgo— hablando sin credenciales,
  y el síntoma habría sido un 401 en plena oficina, no un error de compilación.
  `ApiClient#post` devuelve la respuesta cruda a propósito: el sync-up necesita
  el código y el cuerpo de CADA pedido para reportar por qué se rechazó.
- **`client_search` vivía en el controlador** con SQL crudo, mientras el de
  productos era un scope probado del modelo. "Buscar cliente" tiene relevancia
  propia y otras pantallas la necesitan: como método privado, la siguiente lo
  copia y a partir de ahí buscar un cliente significa dos cosas distintas según
  dónde estés. Movido a `Client.search`, ahora con pruebas de modelo —incluida
  la de que los comodines tecleados se escapan—.
- **La tolerancia de un centavo** estaba declarada como constante y repetida
  como literal en la comprobación de idempotencia de `rueda-api`. Al cambiar
  `TOLERANCE`, esa comparación se habría quedado atrás y empezado a rechazar
  reintentos legítimos con "colisión de idempotencia" — un mensaje que le pide
  al operador RECAPTURAR el pedido.
- **El partial `orders/_field` estaba muerto** y era una trampa: un `yield` en
  un partial sin `layout:` rinde vacío, así que quien lo encontrara y lo usara
  obtendría un campo en blanco. Borrado. Su duplicación real —las seis
  etiquetas del encabezado— se resolvió por el lado que sí importaba: darle
  **nombre accesible** al combo (`label:` → `aria-label`), porque el rótulo
  visible es un `<span>` y el control un `<button>`, así que sin aria un lector
  de pantalla anunciaba los cuatro igual y el aviso "Faltan datos obligatorios:
  Uso de CFDI" no se podía emparejar con ninguno.

### Avisos y salidas (cerrado)

Cinco hallazgos sobre lo mismo: que el usuario pueda **leer** lo que el sistema
le dice y **salir** de donde quedó.

- **El coral bajó a #bd5343** (decisión del usuario, 2026-08-11). Blanco sobre
  el #ce6150 original daba 3.85:1, debajo del 4.5 de AA, y ahí viven los
  botones de confirmación de todos los modales, "Finalizar pedido", el renglón
  Total, el badge Transmitido y los dos avisos de error del paso 1 — los que
  explican qué falta. El tono nuevo **ya estaba en la paleta** como hover, así
  que no se inventó color; el hover bajó a #a84631. Se midió antes de proponer:
  esa medición es la que convirtió una discusión de gusto en una decisión.
- **Los avisos de error ya no se auto-cierran.** Por el flash viajan las
  instrucciones de dos pasos de las guardas del sync —unas 30 palabras, más de
  lo que se lee en 8 segundos— y aparecen arriba al centro mientras el operador
  mira la card que acaba de picar. Los `notice` sí siguen desapareciendo solos:
  son confirmaciones, no instrucciones.
- **Las pantallas 400/404/422/500** pasan de las de Rails —en inglés, sin una
  sola liga y pidiendo "revisar los logs"— a la gramática del proyecto, en
  español y con botón al menú. El botón Atrás tras descartar un pedido llega
  ahí, y sin internet no hay a quién preguntarle.
- **El nombre de la rueda en curso** sale del bloque atenuado: es el único
  lugar de la app donde aparece, y al 60% quedaba en ~2.9:1 con el patrón del
  fondo asomándose. El 60% va al ícono y al título, no al dato.
- **El buscador de cliente recibe el foco** mientras no hay cliente elegido. El
  paso 2 ya lo hacía; faltaba en el campo con el que EMPIEZA cada pedido, y el
  paso 3 ofrece "Capturar otro pedido" justo para no volver al menú.

### El PDF, los cinco hallazgos de un solo archivo (cerrados)

Es el documento que el cliente se lleva en papel y **`render` no se ejecutaba
ni una vez en la suite**: solo se probaba el importe en letra, que es un método
privado. Las pruebas nuevas generan el PDF de verdad y leen su texto.

1. **Fecha en UTC.** Era el único lugar del proyecto que formateaba sin
   `.localtime`: un pedido de las 19:30 salía como del día siguiente a la 1:30,
   en desacuerdo con el reporte en pantalla y con lo que se manda al ERP.
2. **La columna Total no sumaba el Total del pie.** Cada renglón se redondeaba
   al imprimirse pero el pie una sola vez; con 45 partidas la deriva llegaba a
   ~$0.22 y el cliente encontraba centavos de diferencia al cuadrar su copia.
   Arreglado derivando **todo lo impreso de los mismos importes ya redondeados**
   (`printed_items`): así la columna suma el pie *y* Subtotal − Descuento + IVA
   da ese mismo Total. Solo afecta al PDF: lo que viaja al ERP sigue saliendo
   de `Order` a precisión completa.
3. **`inline_format` se comía el texto entre `<` y `>`.** "ENTREGAR ANTES DE
   <5 DÍAS>" se imprimía como "ENTREGAR ANTES DE 5 DÍAS>": la instrucción
   cambiaba de sentido en el papel y nada avisaba. Aplica también a lo que
   viene del ERP (razón social, dirección), que nadie controla desde aquí.
4. **"Página 1" en duro** y la segunda hoja sin logo, folio ni cliente. Con 45
   partidas —el tope, o sea un caso común— son dos páginas: separada del fajo,
   la segunda no se podía identificar.
5. **"UN PESOS"** cuando el total era de $1.xx.

**Trampa al probarlo:** Prawn no emite el texto entre paréntesis sino como
cadenas **hexadecimales** dentro de arreglos `TJ` (los números intercalados son
kerning), y los acentos van en Windows-1252. Un extractor que busque `(…)`
devuelve cadena vacía y **las aserciones pasan por vacuidad si se usa
`assert_no_match`** — otra razón para escribir primero una aserción positiva
que deba encontrar algo.

### La captura se pausa mientras corre un sync (cerrado)

Dos MEDIA de operación que parecían distintas y resultaron ser **la misma**: un
capturista escribiendo mientras corre un sync.

- **Obtener información** vacía el catálogo dentro de su transacción. Un INSERT
  concurrente con FK a un cliente o un producto esperaba el lock y luego
  reventaba con violación de llave foránea: el capturista veía la pantalla de
  error del sistema y no sabía si su pedido existía.
- **Transmitir pedidos** arma el payload, hace el POST y hasta después marca
  `transmitted`. Un pedido `captured` sigue siendo editable por su dueño, así
  que un cambio en esa ventana dejaba al ERP con la versión vieja y a la
  pantalla con la nueva, sin aviso.

Un solo `before_action` cubre las dos. Verlas juntas antes de arreglarlas
ahorró dos mecanismos distintos para el mismo problema.

**Solo se bloquean las escrituras.** Leer un pedido, el reporte y el PDF siguen
disponibles: el operador revisa mientras transmite, y bloquear la lectura sería
un callejón sin salida durante el sync.

**La ventana residual se reporta, no se ignora.** Entre la comprobación y el
commit de una edición todavía cabe una carrera de milisegundos. `Sync::Up`
guarda la huella (`updated_at`) antes de armar el payload y la compara después
del POST; si cambió, el pedido queda transmitido —el ERP ya lo tiene— y sale en
el panel como "revisa este pedido contra el ERP". Es el mismo criterio de todo
el día: cuando no se puede evitar del todo, que al menos no sea silencioso.

### El folio y el vendedor (cerrados)

**El folio se agota y nadie lo sabía.** `format('%04d')` es ancho **mínimo**, no
truncamiento: con el consecutivo en 10000 armaba un folio de 7 caracteres, el
INSERT lo rechazaba y el operador solo leía **"Error interno."**, reintentando
en bucle sin saber que la salida está en el ERP. Hoy el ancho se **deriva**
(`6 − len(prefijo)`) y el agotamiento sale como error de negocio con la
instrucción: "pide que le asignen una clave nueva".

La prueba que existía **consagraba el modelo equivocado** —afirmaba `"ZAB0007"`,
siete caracteres en una columna de seis—, así que había que corregirla junto con
el código. Es el riesgo de escribir la prueba desde la implementación en vez de
desde el dato: la implementación estaba mal y la prueba la protegía.

De paso, acotar la consulta con `id_empresa` y `clave_pedido LIKE 'XX%'` la hizo
sargable: la asignación de folio bajó de ~135 ms a ~27 ms. Con 500 pedidos son
70 s menos de transmisión, y se cerró sola la BAJA de rendimiento.

**El vendedor en 0.** El pedido lleva el vendedor **del cliente**, pero el
export solo traía los de la lista de la rueda: si el cliente venía con uno que
nadie dio de alta en el evento, la app no podía resolverlo y el pedido llegaba
con `id_vendedor = 0` —fuera del índice por vendedor, de sus reportes y de la
comisión— sin error de ningún lado. Cerrado en dos capas: el export ahora trae
la lista **∪** los vendedores de sus clientes, y si aun así el payload llega sin
él, `rueda-api` lo resuelve contra el cliente, que es el dueño del dato.

Medido antes de tocar nada: para la rueda 3 el export nuevo devuelve **los
mismos 15** vendedores y deja 0 clientes sin resolver. O sea que el cambio es
**preventivo**, no correctivo — vale la pena saberlo para no atribuirle un
arreglo que no hizo.

### Las entradas que no se validaban (cerradas)

Cinco MEDIA con la misma forma: la pantalla no ofrece ese valor, pero llega
igual —los combos del encabezado viajan en campos ocultos y el tipo de pedido
en un radio—, y la app o revienta con un 500 o escribe un dato que nunca habría
producido. En el modo con que corre la laptop, ese 500 es **la página de
depuración de Rails servida a toda la LAN**.

1. **`kind` fuera del enum.** No se puede atajar en el modelo: asignar un valor
   desconocido a un enum levanta `ArgumentError` **antes** de cualquier
   validación. Se sanea en `order_params` dejándolo en blanco, y de ahí lo
   recoge `validates :kind, presence: true` por el camino normal.
2. **Perfiles del encabezado de otro cliente.** El pedido llegaba al ERP con el
   RFC de otro contribuyente y el PDF lo imprimía.
3. **`dividir_facturas` fuera del catálogo.** Un `0.01` forjado se transmitía y
   el ERP entiende "divide la factura cada un centavo".
4. **Cantidad fuera del rango de la columna** (`numeric(14,3)`): salía como
   `ActiveRecord::RangeError`, sin rescue. Como es Turbo Stream, la tabla no se
   repintaba y el capturista solo veía que "no pasó nada".
5. **Digest que no es bcrypt.** El sync solo descartaba los vacíos; uno con
   otro formato hacía reventar a BCrypt en el login. Ahora se trata como
   credencial inválida **y** el sync lo manda a "usuarios omitidos", que es
   donde el operador puede verlo antes del evento en vez de descubrirlo cuando
   el capturista no logra entrar.

**Lo que confirmó que valía la pena:** al agregar la validación del catálogo,
dos pruebas existentes empezaron a fallar porque creaban pedidos con montos que
no estaban en él. Eran datos que la pantalla nunca habría producido — la
validación cazó primero a las pruebas.

### `test/system/` arranca con un defecto real (2026-08-11)

Las pruebas de sistema llevaban dos auditorías en el backlog. Se arrancaron
**enganchadas a un defecto concreto** en vez de como tarea de cobertura: el
modal de "Quitar producto" que se cerraba solo. Esa elección es la que hizo que
valieran desde el primer día — la prueba se escribió antes del arreglo, se
corrió contra el código roto y **falló**, así que se sabe que prueba algo.

**El defecto:** el diálogo vive dentro de `#order-detail`, que se repinta con
morph en cada alta, baja y edición de cantidad. El estado "abierto" es un
`style` en línea, e idiomorph lo reescribía con el `display:none` del HTML
nuevo. Se disparaba al corregir una cantidad y tocar el bote de basura de otra
fila: el `blur` manda el PATCH, el clic abre el modal, y la respuesta lo cierra.
Se veía como "el bote de basura no hace nada", y de forma intermitente — sin
edición previa no hay repintado y el modal sí se queda.

**El arreglo:** `data-turbo-permanent` + id estable (`dom_id(item,
:remove_dialog)`, no el `SecureRandom` que traía el partial). Se comprobó que
Turbo **sí** respeta `turbo-permanent` en un morph de stream, cosa que no era
obvia — la duda se resolvió corriendo la prueba, no leyendo el fuente de Turbo.

Se dejó opt-in (`permanent: true` en `home/_confirm_dialog`): los diálogos del
panel del servidor NO deben serlo, porque su mensaje es dinámico —el de
"Obtener información" lleva el número de pedidos que se van a quitar— y
congelarlo sería otro defecto.

### Las dos carreras que perdían pedidos (cerradas)

**1. El rake era invisible para el panel.** `bin/rails sync:down` / `sync:up`
—que el README presenta al mismo nivel que el panel— no creaban `SyncRun` ni
tomaban el lock, así que `SyncRun.running.exists?` daba falso y "Cerrar rueda"
quedaba habilitado encima de una transmisión en curso. Ahora abren su corrida
igual que los jobs, con la guarda **antes** de crearla (regla ya escrita: una
condición que nunca llegó a intentarse no debe quedar como corrida fallida).

**2. "Cerrar rueda" validaba fuera del lock.** Mover la guarda adentro era la
corrección obvia, pero **no cierra la carrera**: la guarda y el borrado son dos
sentencias distintas y `capture!` no toma ese lock, así que un pedido que se
finaliza entre ambas seguía cayendo en `Order.destroy_all`. Lo que sí la cierra
es acotar el borrado a `Order.transmitted` y **volver a comprobar después**: si
algo se coló, la segunda guarda deshace la transacción entera. Nada se pierde;
el operador reintenta.

La alternativa era que `capture!` tomara el mismo lock. Se descartó: mete un
lock en el camino más caliente del evento (finalizar pedido, desde tablet) para
una ventana de microsegundos, y además `update!` sobre una fila ya borrada
devuelve `true` sin excepción, así que habría que reabrir ese caso también.
Acotar el borrado sale más barato y no toca la captura.

**Cómo se comprobó que la prueba prueba algo:** se restauró el código viejo
(`Order.destroy_all`, sin la segunda guarda) y la prueba **falló**. Vale la pena
como método — una prueba de carrera que pasa con el bug presente no sirve de
nada, y la primera versión de esta pasaba por el motivo equivocado (el borrador
ya bloqueaba en la primera guarda, así que nunca llegaba a la carrera).

**Trampa de Minitest:** el scope de un enum vive en el propio singleton de la
clase, así que `remove_method` en un `ensure` lo borra **para el resto del
proceso** y los tests siguientes revientan con `NoMethodError`. Para simular la
carrera se antepone un módulo que se desactiva solo tras la primera llamada.

### Lo que dejaba al operador a ciegas (cerrado)

Tres datos que **ya se calculaban y ninguna pantalla mostraba**. El arreglo no
fue producir información nueva, sino enseñar la que ya existía:

1. **Motivos de la transmisión parcial.** El panel imprimía solo el conteo, así
   que el operador no distinguía un problema de red (reintentar sirve) de uno
   del contenido del pedido (nunca va a servir). Ahora lista folio + motivo en
   un bloque crema, con enlace al reporte filtrado. Dos decisiones dentro:
   - **"✗ Falló" pasa a "✗ Parcial" cuando algo sí entró.** "Falló" a secas
     leía como "no pasó nada" habiendo pedidos ya insertados en el ERP.
   - **Se listan 4 y se dice cuántos faltan.** Un tope silencioso se lee como
     "esos son todos".
2. **`skipped_people`** avisa de capturistas que se quedaron sin universo de
   productos: el defecto llegaba vivo al evento porque nadie lo veía. Junto con
   `purged_orders` se imprime también en el rake, que solo mostraba tres de las
   cinco cifras.
3. **El modal de "Obtener información" dice cuántos pedidos se van a quitar.**
   Como las guardas ya bloquean con borradores o con capturados sin transmitir,
   lo único que puede haber ahí son transmitidos.

**Los pedidos purgados se avisan ANTES, no después** (decisión del usuario,
2026-08-11). El primer intento los reportaba también en el resumen de la
corrida —"Se quitó 1 pedido de esta laptop. Sigue en el ERP."— y el usuario lo
rechazó por dos razones que vale la pena conservar: era **demasiada
información** para un resumen, y **"sigue en el ERP" mezcla dos sistemas** en
un aviso que solo habla de la laptop. La advertencia útil va en el modal,
cuando el operador todavía puede decidir; contarlo después es ruido sobre algo
que ya no tiene vuelta. Criterio general: un aviso sobre una acción
irreversible pertenece al momento de confirmarla.

**Lo que solo se vio al probarlo en el navegador:** los motivos de red llegaban
crudos de Ruby — *"execution expired"*, en inglés y sin sentido para quien está
en el salón. `Sync::Up#failure_reason` los traduce; el detalle técnico se queda
en el log, que es donde sirve. El caso que más importa es el de ActiveRecord:
si falla ahí, **el pedido ya entró al ERP** y lo único que no se guardó es el
folio de vuelta — dato que decide si reintentar es seguro.

Además, `Sync::Up` ahora escribe cada rechazo al log: el resumen de la corrida
vive en `sync_runs`, que "Cerrar rueda" borra, así que el log es el único
rastro que sobrevive al evento.

## 3ª auditoría (2026-08-10) — remediación

Artifact: https://claude.ai/code/artifact/d6dda895-e2d2-4bfb-ab8f-9811a7cd15f2
(3 ALTA · 11 MEDIA · 9 BAJA · 0 vulnerabilidades). Método de siempre: 5
revisiones en paralelo + **verificación de cada hallazgo grave contra el código
en ejecución** antes de publicar — de los 5 reportes, varios "hallazgos" no
sobrevivieron esa segunda pasada.

- [x] **A1 — Producto con empaque mínimo 0 quedaba invendible.**
  `min_sale_quantity.presence || 1` devolvía **0.0**: `presence` sobre un
  decimal cero NO da nil (comprobado en consola). La partida nacía en cantidad
  0, la validación la rechazaba y el capturista veía un error sin haber
  tecleado nada — sin remedio offline. Ahora se exige positivo, el mismo
  criterio que ya usaba `quantity_in_package_multiples`. Tests: 2 de modelo +
  3 de integración (empaque, nil y CERO).
- [x] **A2 — Descargar y transmitir podían correr a la vez y corromper datos.**
  El índice único de respaldo es **por tipo**
  (`index_sync_runs_one_running_per_kind`), así que solo impedía dos `down` o
  dos `up`; un `down` y un `up` simultáneos pasaban ambos el `running.exists?`
  e insertaban sin violarlo. Entonces el replace del sync-down hacía
  `Order.destroy_all` mientras el sync-up transmitía: el pedido entraba al ERP
  pero el `update!` del folio escribía sobre una fila ya borrada —cero filas,
  sin excepción— y **el folio se perdía**. Fix: `SyncRun.exclusively`
  (`pg_advisory_xact_lock` sobre una llave constante) y `SyncRun.start(kind)`,
  que verifica y crea bajo el mismo lock; el controlador ya no hace los dos
  pasos por separado. `CloseRound` usa el mismo lock: entre su `exists?` y su
  `delete_all` podía colarse una corrida nueva y le borraba el registro al job
  recién arrancado. El índice por tipo se conserva como red para dos altas
  idénticas en carrera. Tests: 3 nuevos en `sync_concurrency_test`.
- [x] **A3 — `rueda-api` aceptaba pedidos cuyo encabezado no cuadra con sus
  partidas.** Solo validaba el encabezado CONSIGO MISMO: partidas por $500,000
  con encabezado de $1.00 entraban al ERP y el ERP surtía contra un total que
  no correspondía. Ahora `validate_items!` (cantidad > 0, precio ≥ 0, descuento
  0–100, IVA ≥ 0) y `validate_totals_match_items!` (las cuatro sumas del
  encabezado contra las partidas, tolerancia de un centavo).
  **Verificado que NO rechaza pedidos legítimos:** se construyó el payload real
  de un pedido y las cuatro diferencias dan exactamente `0.0`, también con un
  descuento fraccionario (7.33%) — ambos lados salen de la misma fuente.
  Tests: 5 nuevos; dos payloads viejos de prueba se completaron porque mandaban
  partidas sin importes, cosa que la app real nunca hace.

### Las 11 MEDIA (mismo día)

- [x] **Datos que se perdían en silencio.** El filtro de fecha cerraba el día
  en `23:59:59` y los timestamps de Postgres traen microsegundos: lo capturado
  a las 23:59:59.5 quedaba fuera del mismo día que la pantalla mostraba. Ahora
  el rango es **excluyente hasta el inicio del día siguiente**. Y el calendario
  conservaba una **selección a medias** al cerrarse: la etiqueta decía
  "10/08/2026 — …" sin haber filtrado, y al reabrir el primer toque cerraba el
  rango contra esa fecha olvidada — ahora se descarta en `close()`.
- [x] **Robustez del reporte.** Los enlaces del paginador se armaban con el
  hash CRUDO de la petición: bastaba un `?host=` en la URL para que Rails los
  generara como URLs absolutas a ese dominio (y un `?controller=` reventaba la
  pantalla). Ahora recibe `base_params` = los filtros ya saneados. Y una página
  fuera de rango daba la pantalla de error de Rails: `rescue_from
  Pagy::OverflowError` redirige a la primera conservando los filtros.
- [x] **N+1 en la tabla de partidas:** cada renglón pedía su producto por
  separado — 45 consultas en CADA repintado, o sea en cada edición de cantidad,
  desde una tablet. `has_many :order_items` precarga `:product`. Medido: de una
  consulta por partida a **una sola**.
- [x] **Tabla del reporte en tablet:** nueve columnas sin adaptación dejaban
  Total y Estatus fuera del viewport. Hora y Vendedor se ocultan bajo `lg`,
  igual que la tabla de partidas del paso 2.
- [x] **Regreso al reporte:** `report_back_path` (helper de
  ApplicationController) lee el referer **validando el host** y pinta "← Volver
  al reporte" en el pedido; conserva filtros, estatus y página. Antes, el
  servidor que revisa pedidos antes de transmitir tenía que rearmar los siete
  filtros en cada regreso, y el capturista viendo un pedido propio no tenía
  ningún botón de salida.
- [x] **Estado vacío ambiguo:** "No hay pedidos capturados" se leía como que se
  habían perdido. Ahora distingue "Todavía no hay pedidos capturados" de
  "Ningún pedido coincide con lo que elegiste" + "Quitar filtros".
- [x] **Un pedido, un folio.** Convivían tres precedencias (el paso 2 prefería
  el del ERP, el paso 3 y el PDF el local, el reporte solo el local): el mismo
  pedido se llamaba distinto según la pantalla. `Order#folio` es la única
  fuente, con el `"(borrador)"` adentro.
- [x] **`server/rounds.html.erb`** rompía tres normas visuales: armaba su
  propio encabezado (sin barra superior), centraba a `max-w-4xl` en vez del 5%
  y pintaba las ruedas en `bg-white/5`. Migrada al shell único con la gramática
  de card (marco dorado + cuerpo crema) y el `data-controller="modal"` movido a
  un wrapper neutro, que es lo que permite el hover sin romper el diálogo.
  Test que fija las tres cosas.
- [x] **`CLAUDE.md` describía un modelo que no existe** ("ID local UUID",
  estado `pendiente`): es el archivo que se carga en cada sesión. Corregido a
  folio local `RN-000123` y estados `draft`/`captured`; el renglón equivalente
  de esta bitácora quedó marcado como superado.

### Las 9 BAJA (mismo día)

- [x] **Parámetros de URL sin validar de tipo:** `?user_id[]=1` daba 500 (un
  arreglo no responde a `to_i`) y `?client_id=abc` se volvía 0, filtrando hacia
  la nada y quedándose pegado en todos los enlaces. Ahora solo se aceptan texto
  o número, y un id no numérico se descarta. **Rango invertido** (`desde >
  hasta`) se endereza en vez de devolver vacío sin explicación.
- [x] **`erp_person_id = 0` reservado:** el sync-down excluye ese id del alta
  masiva de usuarios — si el ERP mandara una persona con id 0, el upsert le
  sobrescribía usuario y contraseña a la cuenta `server` **conservando el rol**,
  y el operador perdía el acceso sin aviso.
- [x] **Un fallo local ya no aborta el lote** del sync-up (`ActiveRecordError`
  en la lista de rescates por pedido); antes el primero quedaba insertado en el
  ERP y los demás ni se intentaban.
- [x] **El barrido de corridas huérfanas** solo corre con el adapter de jobs en
  proceso: con un worker aparte (producción) un reinicio marcaría "interrumpida"
  una corrida viva y liberaría la guarda de "una a la vez".
- [x] **Los jobs ya no vuelcan la excepción cruda al panel** (clase, rutas
  internas, IPs): guía accionable en pantalla, `full_message` al log.
- [x] **Interacción:** el calendario se opera con teclado (`click` además de los
  eventos de mouse: Enter/Espacio disparan click y NUNCA mousedown); el combo
  solo enfoca su campo de filtro con más de 8 opciones (en tablet levantaba el
  teclado para un combo de tres); las tarjetas de estatus dicen "Ver solo
  estos"/"Quitar filtro" y usan `aria-current` (`aria-pressed` no es válido en
  un enlace); foco visible en los tres buscadores; "Capturar otro pedido" en el
  paso 3; y el aviso de cliente sin datos fiscales ahora dice qué hacer.
- [x] **Foco al quitar una partida** (era lo único que había quedado pendiente):
  el botón que abre el modal vive DENTRO de la fila, así que al borrarla el
  `modal#close` no tenía a dónde devolver el foco y caía al `<body>` — había que
  retabular desde el inicio de la página en cada baja. Solución: un elemento
  vacío `#focus-director` que `OrderItems#destroy` **reemplaza** (no morphea) con
  un partial que trae `data-controller="focus"`; al insertarse, Stimulus lo
  conecta y mueve el foco al buscador, que es la acción natural siguiente. El
  truco está en el `replace`: con morph el nodo se conserva y `connect()` no
  volvería a correr. Solo viaja en la baja, así que editar cantidad o descuento
  sigue sin mover el foco (validado en navegador con clics reales, y con test
  de ambos casos).
- [x] **Consistencia:** `accessible_orders` vive en `ApplicationController` y lo
  usan los dos controllers (antes la misma expresión con dos nombres);
  `client_from_key` extraído (el parseo estaba duplicado en `new` y `edit`);
  `items_label` resuelve sus propios nombres (la vista los buscaba recorriendo
  el array del combo); íconos sueltos → Heroicons inline; `pedido(s)` →
  `pluralize`; **rubocop en cero ofensas** en ambos repos.
- [x] **Documentación:** el mapeo del detalle decía `code` cuando se envía
  `product.erp_product_id` (`code` es el padded de 6 dígitos, solo para
  mostrar); el paso 5 de la guía de la laptop quedó marcado OPCIONAL (la API
  vive en el servidor de testing).

### Idioma del código — regla escrita (a raíz de la auditoría)

El hallazgo de nomenclatura mezclada era mío y yo seguía reincidiendo, así que
la regla quedó en `docs/convenciones-codigo.md` (que sí se carga siempre):
**identificadores en inglés; español solo en comentarios y en el texto que ve
el usuario**, con `dividir_facturas` como única excepción registrada (espeja la
columna del ERP). Se normalizó el código nuevo Y el viejo de las vistas.

**Trampa del barrido:** hacerlo con expresiones regulares tocó texto visible y
comentarios ("Ningún pedido **coincide**" → "matching"); lo cazó la suite, pero
conviene revisar el diff palabra por palabra. Y una continuación de línea estilo
Ruby (`\`) se coló en JavaScript: **`node --check` existe en la máquina** aunque
el proyecto no necesite Node en runtime — usarlo tras tocar los controllers.

Suites tras la remediación: rueda-negocios **163/599**, rueda-api **27/79**,
rubocop limpio en ambos. (Cifra de ese día; hoy son otras — no se actualiza
porque envejece con cada commit y la suite ya es su propia fuente de verdad.)

## Decisiones tomadas

- **Forma de trabajo:** flujo PAIVD. No edit/write sin aprobación previa del
  usuario en el turno.
- **Proyecto independiente:** no aditivo al b2b; b2b es solo referencia.
- **Arquitectura:** una laptop = servidor LAN; app + Postgres local; los
  demás equipos apuntan por navegador. Offline resuelto a nivel de red.
- **App (`rueda-negocios`):** Rails 8 + Hotwire + Tailwind + Postgres + bcrypt.
- **API (`rueda-api`):** Sinatra + Sequel + pg contra la BD del ERP; expone
  export del dataset + creación de pedidos en el ERP.
- **Sync desde la oficina** (antes/después del evento) por defecto; evento
  100% offline.
- **Sync transporte-agnóstico:** LAN o internet configurable (URL + token).
  Seguridad/hardening → fase posterior de strengthening (diferido).
- **IDs de pedido:** UUID local generado offline; folio ERP se asigna al
  transmitir; se guarda el mapeo. Transmisión idempotente y reintentable.
  *(Superado: nunca hubo UUID. El identificador offline es `local_folio`
  `RN-000123` (`Order#generate_local_folio`) y los estados son `draft` →
  `captured` → `transmitted`; lo del folio del ERP y la idempotencia sí
  aplica.)*
- **Estructura: dos repos separados** (convención b2b, uno por deployable):
  - `_fecego/rueda-negocios/` — app Rails de la laptop; incluye las rake
    tasks de sync (down/up). No hay repo de sync aparte.
  - `_fecego/rueda-api/` — API Sinatra on-prem (plantilla api-v2).
  - Contrato compartido (JSON de export + alta de pedidos): documentado en
    `docs/erp-esquema-catalogos.md` y `docs/erp-esquema-pedidos.md` (este repo).
    (El `rueda-api/docs/contract.md` planeado nunca se creó — 2ª auditoría M9.)
- **Ignorado:** `_fecego/offline/local.sqlite` (spike previo, no forma parte
  del proyecto).

### Descubrimiento del esquema de catálogos (ERP) — decisiones

Detalle completo en `docs/erp-esquema-catalogos.md`. Puntos duros:

- **BD:** `psql -p 1702 -d fecego` (Postgres.app), esquema `fecego`.
- **`id_empresa = 1` siempre.** Toda PK arranca con `id_empresa`; borrado
  lógico con `baja = false`.
- **La rueda ya existe nativa en el ERP** (6 tablas `cnf_rueda_negocios*`):
  cabecera + proveedor/marca/vendedor/cliente/persona. No es concepto nuevo.
- **Mapa de entidades:** clientes=`vta_cliente`, login=`cnf_persona` +
  `cnf_persona_has_metodoidentifica` (¡sin guion bajo!), vendedores=
  `vta_vendedor` (→`cnf_persona` vía `id_persona`), proveedores=
  `com_proveedor`, marcas=`com_marca` (NO `cnf_marca`), productos=
  `com_producto`, precios=`com_producto_has_precio`.
- **SKU oficial de FECEGO = `com_producto.id_producto`** (la PK). NO usar
  `com_producto_has_sku` como código oficial (ese es el SKU del proveedor).
- **Login SIEMPRE** vía `cnf_persona`/`cnf_persona_has_metodoidentifica`,
  nunca `vta_vendedor`.
- Relación producto→marca directa (`com_producto.id_marca`); producto→
  proveedor por puente (`com_proveedor_has_producto`).

### Fase A — scaffolding app `rueda-negocios` (decisiones)

- **Toolchain:** Ruby **3.3.7** (rbenv, `.ruby-version`, igual que el servidor
  y b2b), Rails **8.1.3**, Postgres **17** local en **puerto 1702** (Postgres.app,
  rol `fecego`, mismo cluster que b2b). Bases propias `rueda_negocios_{development,test}`.
- **Stack:** Rails 8 + Hotwire (importmap) + Tailwind + pg + bcrypt + dotenv-rails.
  `database.yml` parametrizado por ENV (`.env`, gitignored; `.env.example` versionado).
- **Modelos en inglés, diseño limpio:** se descarta la estructura del ERP
  (sin `id_empresa`, sin auditoría). Cada tabla preserva su llave de negocio del
  ERP como `erp_*` con índice único (para upsert del sync y mapeo de identidad).
- **Entidades:** `User`, `BusinessRound`, `Salesperson`, `Client`, `Supplier`,
  `Brand`, `Product`, `Price` + uniones `ProductSupplier`, `BusinessRoundClient`
  y puentes HABTM (brands_suppliers, business_round_{suppliers,brands,salespeople}).
- **Producto (según requerimiento):** Código FECEGO (`erp_product_id`),
  descripción, número de parte, unidad, marca, **mínimo de venta**, **descuento
  tope**, existencia. **Proveedores y SKUs de proveedor** → modelo de unión
  `ProductSupplier` (con `supplier_sku`), no HABTM puro.
- **Price:** un solo registro activo por producto (índice único en `product_id`),
  reducido a **precio público + mayoreo** (lo que pide el requerimiento).
- **Login (Fase B):** `has_secure_password` NO cableado; `User.password_hash`
  guarda el hash del ERP. Falta confirmar el algoritmo (¿bcrypt?) antes de
  implementar `authenticate` — el `varchar(256)` del ERP sugiere que podría no
  ser bcrypt. [[erp-esquema-catalogos]]

### Fase B — arco login (decisiones)

- **Hash del ERP es bcrypt** (confirmado por el usuario) → columna renombrada a
  `password_digest` y `has_secure_password validations: false` en `User`. Se
  valida directo sin re-hashear; `validations: false` porque el usuario entra
  por sync (solo trae el digest), nunca se fija contraseña desde la app.
- **Sesión** por `session[:user_id]`; `SessionsController` (layout `auth`),
  `require_login` global en `ApplicationController`, `reset_session` en
  login/logout. Usuarios inactivos no entran.
- **Diseño:** tomado de `docs/design-reference/login`. Assets copiados a
  `app/assets/images` con nombres propios: `fecego_logo_white.png`,
  `tools_pattern_white.svg` (era `13.svg`; el `12.svg` es la versión negra),
  `event_card_oaxaca.svg` (tarjeta del evento; luego dinámica por rueda).
  Regla del usuario: **al copiar assets, renombrarlos con nombre adecuado**.
- **Paginación:** gem `pagy` agregado (aún sin uso; para los listados futuros).
- **Seed dev** (`db/seeds.rb`, solo development): rueda activa Oaxaca 2026 +
  usuario `capturista` / `rueda2026`. Placeholder hasta el sync real (Fase D).
- **Placeholder post-login:** `HomeController#index` (destino de login) — mínimo,
  se reemplaza cuando lleguen las pantallas de navegación.
- **Tests:** `test/integration/authentication_flow_test.rb` (5 casos, verdes).

### Fase B — arco menú (decisiones)

- **`home#index` = menú** ("¿Qué quieres hacer hoy?"), landing autenticado.
  Usa el layout `auth` (shell oscuro full-bleed, reusado del login).
- **4 opciones** (= arcos futuros): Registrar pedido (tarjeta coral), Reportes
  de venta, Asistencia de clientes, Generar cotización (amarillas). Partial
  `home/_menu_card`. Hoy enlazan a `#`; se cablean cuando se construya cada una.
- **Assets** copiados a `app/assets/images` con nombres propios: `expo_illustration.svg`
  e `icon_{register_order,sales_reports,client_attendance,generate_quote}.svg`.
- **Barra superior:** logo + pills `Usuario` (real, `current_user`) y `Proveedor`
  + `Cerrar sesión`.
- **Proveedor del capturista** (pill) — RESUELTO: modelado con
  `BusinessRoundPerson` (mapea `cnf_rueda_negocios_persona`, tabla
  `business_round_people`): liga `User` (persona) ↔ `Supplier` ↔ `BusinessRound`
  (+ marca opcional, `position` = el `consecutivo` del ERP).
- **Multi-proveedor:** un capturista puede representar a **varios** proveedores
  (el ERP lo permite vía `consecutivo` → local `position`). `User#suppliers_in(round)` devuelve
  todos. Se maneja con un **proveedor activo por sesión** (`session[:supplier_id]`):
  helpers `active_round` / `available_suppliers` / `current_supplier` en
  `ApplicationController`; 1 proveedor → autoselección, >1 → **selector** en el
  pill (`shared/_supplier_pill`, controller Stimulus `form-submit`, ruta
  `PATCH /active-supplier` → `ActiveSuppliersController`).
  **Hoy el proveedor activo es solo contexto/etiqueta: NO restringe la captura**
  (un pedido puede mezclar proveedores). Regla a definir si cambia.
- **Seed dev:** liga al capturista con 2 proveedores (Hitools, Truper) para
  probar el caso multi.

### Fase B — hub de reportes (decisiones)

- **`ReportsController#index`** en `/reportes` (layout `auth`; hoy `/reports`). La card
  "Reportes de venta" del menú enlaza aquí.
- **Patrón de pantalla interna:** header amarillo full-width (título + logo que
  regresa al menú; logo blanco con `invert` sobre el amarillo) + cuerpo negro
  con patrón + contenido centrado. Minimalista (sin pills de usuario/proveedor
  ni logout, por decisión del usuario).
- **4 sub-reportes** (tarjetas cuadradas amarillas, partial `reports/_report_card`):
  Pedidos capturados, Reporte de asistencia, Reporte de productos, Reporte de
  ventas. Enlazan a `#` (cada reporte se construye después).
- Íconos negros uniformes vía `brightness-0` (el asset de "ventas" venía coral).
  Assets: `icon_{captured_orders,attendance_report,products_report,sales_report}.svg`.

### Fase B — Pedido, Arco 1 / encabezado (decisiones)

- **`Order`** (borrador): belongs_to user (capturista) / business_round / client.
  **NO lleva proveedor** — un pedido puede mezclar productos de varios
  proveedores; el proveedor activo es solo contexto de sesión. `kind`
  (invoice/remission), `status` (draft/submitted; hoy draft/captured/transmitted),
  `erp_folio` (nulo hasta sync).
- **Datos fiscales del cliente** (nuevos modelos): `ClientTaxProfile` (RFC +
  razón social + uso CFDI default), `ClientReceiptProfile` (remisión),
  `ClientBranch` (sucursal), `CfdiUse` (catálogo SAT), `Client.email`. Todos con
  `erp_*` para el sync (mapeo fino con el ERP se valida en el arco de sync).
- **Paso 1 (`orders#new`):** tema **claro/crema** (patrón negro `tools_pattern_black.svg`,
  copiado de `12.svg`), header amarillo. Dos paneles: "Datos del cliente"
  (clave → carga; Factura/Remisión con toggle Stimulus `order-kind`; CFDI; RFC/
  razón social; dirección) y "Catálogo de clientes" (busca por nombre → clave/
  nombre/vendedor). Defaults: is_default o primero; CFDI = default del RFC.
- **Validación** en `Order` (`header_selections_present`): Factura exige RFC +
  CFDI; Remisión exige remisión (si hay); sucursal obligatoria si el cliente
  tiene. Al guardar → `orders#show` (resumen; placeholder de paso 2).
- La card "Registrar pedido" del menú enlaza a `orders#new`.
- **Seed:** 2 clientes demo — C0001 (2 RFC, 2 sucursales) y C0002 (uno de cada)
  — + catálogo CFDI (G01/G03/P01) + vendedor.

### Fase B — Pedido, Arco 2 / detalle (decisiones)

- **`OrderItem`** (partida): snapshot de código/descripción/no.parte/unidad/precio/
  IVA (`tax_rate`) del producto al agregarlo. `position` = consecutivo. Line total
  = cantidad × precio (descuento e IVA se aplican al agregado, como la referencia).
- **Datos nuevos:** `Product.model` (modelo, para búsqueda), `Price.tax_rate` (IVA,
  del ERP `com_producto_has_precio.iva`), `Order.observations`.
- **Totales en `Order`:** subtotal=Σ(cant×precio); descuento=Σ(línea×%); **IVA=
  Σ(base×tax_rate del producto)**; total=subtotal−descuento+IVA. (Los números de
  `paso2.png` eran ilustrativos; se validará el manejo fiscal exacto en el sync.)
- **Búsqueda de producto** (`Product.search`): código FECEGO (`erp_product_id`),
  código proveedor (`product_suppliers.supplier_sku`), nombre (`description`),
  modelo, número de parte.
- **Pantalla `orders#show`** (paso 2, tema claro): resumen del encabezado + buscador
  de producto con autocompletado + tabla de partidas (todas las columnas, bordes
  redondos, borrar por fila, editar cantidad/descuento en línea) + totales +
  observaciones. **Interacciones vía Turbo Streams** (`OrderItemsController`
  create/update/destroy → reemplaza `#order-detail`). Auto-guardado de observaciones.
- Botones: **Editar** → paso 1; **Cancelar** → menú (turbo_confirm); **Enviar** →
  `#` (Arco 3). (Superado: hoy Cancelar abre un modal accesible que DESCARTA el
  borrador —`Orders#destroy`, M15— y el botón final es "Guardar" → `capture`.)
- **Seed:** 5 productos demo (con precio, IVA 16%, modelo, No. parte, SKU proveedor).
- **Consecutivo sin huecos (2026-08-10):** borrar una partida intermedia dejaba
  hoyos en la columna Consecutivo. `Order#renumber_items!` reacomoda a 1..N y
  se llama desde `OrderItems#destroy`. Usa `update_column`: no es un cambio de
  negocio sino de orden, y una partida con algún problema previo no debe
  bloquear la renumeración del resto. Alcance real medido antes de tocar nada:
  `position` **solo se muestra** en esa columna — el PDF no la lleva y el
  payload del sync-up ya numera `1..N` con `with_index(1)`, así que el ERP
  nunca vio huecos.
- **Tope de 45 partidas por pedido (2026-08-10):** regla de **negocio** de la
  rueda, NO del ERP — medido: el histórico del ERP llega a 287 renglones y
  tiene 3,177 pedidos con más de 45. El usuario confirmó que la regla opera
  hoy y que **puede subir cuando entren los regalos por promoción**; y que
  aplica solo a partidas (renglones), nunca a cantidades. Implementación:
  - `Order::MAX_ITEMS = 45` + `Order#items_count_for_limit` /
    `#items_limit_reached?` — **punto único** de la regla. Cuando lleguen los
    regalos, ahí se decide si se excluyen del conteo o si solo sube la
    constante, sin perseguirla por modelo/controlador/vista.
  - Validación en `OrderItem` **`on: :create`**: un pedido que ya rebase el
    tope (si la regla bajara) sigue siendo editable — se pueden corregir
    cantidades y quitar renglones — en vez de quedar atorado. Va en el modelo
    y no solo en el controlador: cubre POST forjado (validado en navegador:
    rebota con el aviso aunque el buscador esté deshabilitado). No hubo que
    tocar `OrderItemsController#create`: su rama `else` ya muestra
    `errors.full_messages` en el flash.
  - UI: contador `Partidas 12 / 45` siempre visible **dentro del buscador**, al
    extremo derecho del pill (decisión del usuario; primero se probó como
    encabezado de la tabla y arriba del buscador), y buscador deshabilitado con
    placeholder "Alcanzaste el máximo de 45 partidas". El **60%** de
    deshabilitado va sobre el control (lupa + campo) y NO sobre el pill
    completo: el contador es información, no control, y debe quedar legible
    justo cuando se alcanza el tope. El buscador se extrajo a
    `orders/_product_search` con id propio y se repinta con **morph** en
    `detail_streams` — con `replace` se reconectaría el controlador Stimulus,
    que al conectar enfoca el buscador, y le robaría el foco a la tabla en cada
    edición de cantidad/descuento (validado: el foco se queda en el input).

### Fase B — Pedido, Arco 3 / envío + resumen (decisiones)

- **`Order.submit!`** (hoy `capture!` → `status: captured`): exige ≥1 partida + asigna
  **`local_folio`** (`RN-000123`, offline; el `erp_folio` llega en el sync).
  `Order#folio` = local o erp.
- **`orders#submit`** (hoy `orders#capture`, botón "Guardar") → **`orders#summary`** (paso 3).
- **Paso 3 (`summary`)**: panel "Resumen del pedido" con folio + 3 opciones
  (Generar PDF / Enviar por correo / Enviar por WhatsApp) + Terminar (→ menú).
- **Enviar por correo = MODAL** (Stimulus `modal`): correo registrado + input para
  otro. (Superado: hoy correo/WhatsApp son placeholders deshabilitados
  "Próximamente" —M7 de la 1ª auditoría—; el modal se retiró.)
- **Generar PDF:** implementado con **prawn** (`Pdf::OrderGenerator`, offline).
  **Replica el formato IMPRESO del ERP** (muestras `PedidoKE*.pdf` del b2b, en
  `portal-v2/tmp/letter_opener`): logo fecego + datos de empresa, "PEDIDO" +
  CLAVE/Fecha, bloque cliente (POR FACTURAR/RFC/razón social o remisión) +
  atributos (capturado/transmitido/vendedor/estatus), tabla con bordes
  (Código/Descripción/Unidad/Cantidad/Precio/Monto/%Dto./Subtotal/%IVA/Total),
  **importe en letra** (conversor español propio) y totales. `orders#pdf` →
  descarga. Íconos `icon_{pdf,mail,whatsapp}.svg`.
- **Logo oscuro:** `fecego_logo_dark.png` = `logo_fecego.png` del b2b (blanco)
  invertido a negro (con chunky_png, una vez) para el PDF en fondo blanco.
- **Diferido:** envío por **correo** real (SMTP; offline se difiere al sync) y
  **WhatsApp** (stub). Los botones existen y responden.

### Fase B — reporte "Pedidos capturados" + roles (decisiones)

- **Rol en `User`** (enum `role`: `capturista` | `server`, default capturista).
  `User#can_see_all_orders?` = `server?`. Mapeo fino con el ERP (`cnf_persona.id_rol`)
  se define en el sync.
- **Regla validada (importante para rueda-api / uso real):** un **capturista ve
  solo SUS pedidos** (`current_user.orders`); el **equipo-servidor ve TODOS**
  (`Order.all`) — para transmitirlos al ERP. `ReportsController#captured_orders`
  (`/reportes/pedidos-capturados`, hoy `/reports/captured-orders`, card del hub) con badge "Mis pedidos" /
  "Todos los pedidos".
- **Seed:** usuarios `servidor` (rol server) y `capturista2`, + un pedido de
  capturista2 para demostrar el scoping. Ambos con `rueda2026`.
- **Resumen por estatus + paginador (2026-08-10):**
  - El paginador ya existía (25 por página) pero se **ocultaba con una sola
    página**, así que en desarrollo parecía no existir. Ahora el conteo se
    muestra siempre —saber cuántos hay es dato útil por sí mismo— y la
    navegación aparece solo cuando hace falta. Se agregaron números de página
    con elipsis (`@pagy.series`) y selector de 25/50/100 (lista cerrada: por
    URL nadie debe pedir 5,000 renglones). Partial `shared/_paginator`,
    reutilizable.
  - **Los enlaces se arman con `request.query_parameters.merge`**, no solo con
    `page:`: así los filtros que vienen en el backlog sobrevivirán al paginar
    sin tocar el partial. *(Superado: la 3ª auditoría lo cambió por
    `base_params` —los filtros ya saneados—, porque el hash crudo de la
    petición permitía inyectar un `?host=` en los enlaces del paginador.)*
  - **Resumen ARRIBA de la tabla, no dentro del paginador** (decisión
    discutida con el usuario): son dos trabajos distintos —el paginador dice
    dónde estás en el listado, el resumen cómo va el conjunto— y juntos se
    leería ambiguo ("¿este total es de la página o de todo?"). Además el
    paginador se oculta con una sola página, que es justo cuando el resumen sí
    importa. Orden de lectura: agregado → detalle → navegación.
  - **`Order.totals_by_status` agrega EN SQL** (`ITEMS_TOTAL_SQL`, la misma
    fórmula de `OrderItem#total`): `Order#total` se calcula en Ruby, así que
    totalizar con él obligaría a cargar cada pedido con sus partidas (300
    pedidos × 45 renglones) en cada apertura. Devuelve siempre los tres
    estatus, con ceros los vacíos, porque las tarjetas serán también el filtro
    de estatus.
  - **`ReportsController#orders_scope` es el ÚNICO lugar que arma el alcance**
    — listado, resumen y conteo del paginador salen de ahí y no pueden
    divergir. El mismo reporte sirve a los dos roles: el capturista ve el
    resumen y el paginador de SUS pedidos; el servidor, de todos.
- **Filtros del reporte — entrega 1 (2026-08-10):** usuario crea, cliente,
  vendedor, fecha crea (rango) y estatus, en `OrdersFilter` (`app/queries/`).
  - **Se aplican SOBRE el scope ya acotado por rol**, así que un capturista no
    puede filtrar hacia pedidos ajenos ni por URL. El combo "Usuario crea"
    solo se le ofrece al servidor: al capturista le mostraría nombres que no
    puede consultar. Ambos casos con test.
  - **El estatus se aplica aparte** (`apply_status`): el resumen se calcula con
    todos los demás filtros pero SIN él, porque sus tarjetas **son** el filtro
    de estatus y deben seguir mostrando el panorama completo para poder saltar
    entre ellas (volver a picar la tarjeta activa lo quita).
  - **Las fechas se interpretan en hora LOCAL**, igual que la columna Fecha del
    reporte (`created_at.localtime`). Con `Time.zone` en UTC, un pedido
    capturado a las 19:00 del día 10 se guarda como 01:00 del 11: filtrar en
    UTC lo dejaría fuera del mismo día que la pantalla le muestra al usuario.
    Test con esa hora exacta.
  - **El formulario no lleva `page`:** cambiar un filtro regresa a la primera
    página; si no, se cae en una página que ya no existe y la tabla sale vacía.
    El `per_page` sí viaja.
  - Los catálogos de una rueda son chicos (3 capturistas, 15 vendedores, 47
    clientes), así que van en combos con filtro de texto — se descartó el
    buscador que se había propuesto para cliente. Solo producto lo necesitará
    (13,222).
  - **Trampa de tests:** el renglón "No hay pedidos capturados" también es un
    `<tr>`; contar `tbody tr` daba 1 con la tabla vacía y escondía un fallo.
    Se descarta por su celda con `colspan`.
- **Filtros del reporte — entrega 2 (2026-08-10):** proveedor, marca y
  producto. No son del pedido sino de sus partidas ("pedidos que traen al menos
  una partida de MAKITA").
  - **Los tres se reducen a un conjunto de productos** (`matching_products`,
    intersección de los tres) y se aplican con `WHERE orders.id IN (SELECT
    order_id FROM order_items WHERE product_id IN …)`. **Nunca con un JOIN a
    `order_items`:** unir repetiría el pedido por cada partida que coincida en
    la tabla e inflaría el importe del resumen, que ya hace su propio join
    para sumar.
  - **Decisión del usuario: con un filtro de partida activo, los importes son
    los de las PARTIDAS QUE COINCIDEN, no los del pedido completo.** Quien
    pregunta "¿cuánto vendió MAKITA?" quiere la venta de MAKITA, no el tamaño
    de los pedidos donde aparece — y con dos proveedores los totales se
    traslaparían. Aplica al resumen, a la columna Total y a Renglones.
  - Como el mismo número pasa a significar otra cosa, **la pantalla lo dice**:
    "Importes de las partidas de MAKITA" arriba del resumen.
  - En el resumen la restricción va como **`CASE` dentro del `SUM`**, no como
    condición del join, para que el conteo de pedidos no cambie. Los importes
    por pedido de la página salen de **una sola consulta agrupada** para los 25
    visibles, no de recalcular pedido por pedido.
  - **Producto es buscador con autocompletado** (no combo: son 13,222).
    Sugiere conforme se teclea (`GET /reports/product-options`, reusando el
    controller `autocomplete` del paso 2) y al elegir una opción escribe su
    **código** en el campo y filtra — el código va a 6 dígitos, así que como
    texto de búsqueda identifica a ese producto y a ningún otro. Se conserva el
    texto libre: "disco flap" acota a esa familia entera, que un selector de un
    solo SKU no podría. Las sugerencias se acotan al universo de quien mira.
    (Primero se hizo solo como campo de texto; el usuario pidió ver y elegir
    coincidencias.)
  - El aviso enuncia distinto el producto: "Importes de las partidas de MAKITA"
    (proveedor/marca) vs "…que coinciden con \"037857\"" — un código suelto
    tras "de" se lee como si fuera un proveedor.
  - Proveedor y marca se ofrecen del **universo de quien mira**
    (`available_suppliers`/`available_brands`): al capturista no se le muestran
    opciones que jamás podrían aparecer en sus pedidos. El índice de
    `products.brand_id` ya existía.
  - **Trampa de tests:** los folios locales con `rand` chocaban contra el
    índice único de `local_folio` y el test fallaba de forma intermitente —
    secuencia correlativa.
  - **Estética, en tres pasadas con el usuario (mismo día):**
    1. Filtros y tarjetas se habían hecho con paneles translúcidos
       `bg-white/5`, que sobre el shell negro con patrón se lavan ("no se
       aprecian bien"). Norma en `docs/convenciones-visuales.md`.
    2. Se retomó la card del levantamiento de pedido: marco dorado con **sus
       mismos márgenes** (`p-6 sm:p-8`) y los controles directamente sobre el
       dorado, **todos del mismo fondo** (pill negro) — antes unos eran negros
       (combos) y otros blancos (campos de escritura), y se veía disparejo.
       Las tarjetas de estatus quedaron crema con su badge de color y la de
       Total en **coral**, igual que el renglón Total de la card de totales.
    3. **Compactada:** fuera el título "Filtros" y fuera las etiquetas arriba
       de cada campo — el nombre de la dimensión va DENTRO del control como
       hint ("Todos los proveedores"), que es la línea que se ahorra por
       filtro. Y **filtra al seleccionar** (`change->form-submit#submit`), así
       que desapareció el botón "Filtrar"; solo queda "Limpiar filtros", con
       `justify-self-start` para que la celda del grid no lo estire y una
       acción secundaria no pese más que los filtros.
  - Los tres filtros de partida van juntos en el orden: mezclados con los del
    pedido confundían qué acota qué.
  - **Selector de rango de fechas hecho a mano** (`date_range_controller` +
    `shared/_date_range`): un solo control con calendario de un mes, rango por
    **arrastre** (escritorio) o **clic-clic** (tablet, donde arrastrar es
    incómodo). Se descartó vendorear Flatpickr: el proyecto no tiene ninguna
    dependencia de JS externa (combo, autocompletado y modal están hechos a
    mano) y su CSS habría que sobrescribirlo casi por completo.
    - Al completar el rango escribe los hidden y **dispara `change` en el
      `from`**, que es lo que hace que el formulario filtre solo. El partial
      recibe `input_data` para esa acción: sin eso el evento burbujea al form
      pero nadie lo escucha (los controles llevan la acción uno por uno, y no
      el form completo, para que el campo de filtrar opciones del combo no
      dispare envíos de más).
    - **Trampa del preview:** el día bajo el cursor no se marcaba durante el
      arrastre — `end` sigue nulo, así que no era "extremo" ni caía "dentro"
      del rango. Hay que tratar `hover` como extremo mientras `dragging`.
    - **Trampa grande (la reportó el usuario: "sigue sin seleccionar la
      segunda fecha"):** el grid se reconstruía en cada movimiento y en cada
      selección. Eso destruye el botón que está bajo el cursor, y como
      **Stimulus enlaza las acciones de los nodos nuevos de forma asíncrona**
      (MutationObserver), el clic siguiente caía en un botón todavía sin
      acción y el segundo día no se registraba — intermitente y **invisible
      con eventos sintéticos**: solo apareció al probar con clics reales del
      mouse. Fix: el grid se **construye** solo al abrir o cambiar de mes
      (`buildGrid`) y la selección solo **repinta clases** (`paint`). Regla
      general: no reconstruir DOM que está recibiendo eventos de puntero.
    - **Rango de un solo día:** dos clics sobre el mismo día. La etiqueta
      muestra una sola fecha, no "X — X".
    - **Hoy siempre marcado** con anillo coral, aunque no sea parte del rango:
      es la referencia para ubicarse. Y sin rango elegido, el calendario abre
      en el mes actual.
    - Todo en fecha **local**: `new Date("2026-08-10")` se interpreta como UTC
      y en México adelanta un día; se parte el ISO a mano.

### Sistema visual y detalles de pantalla (decisiones)

Las **normas** que salieron de aquí viven en `docs/convenciones-visuales.md`
(shell, roles por color, iconografía, hover, deshabilitado al 60%, pills,
textos al usuario) — se cargan solas. Aquí queda el porqué y lo específico de
cada pantalla.

- **Origen (2026-07-27/28):** el sistema visual se iteró **en vivo con el
  usuario** tras migrar todo al shell oscuro; varias reglas nacieron de que él
  detectara inconsistencias entre pantallas ("no hay consistencia entre
  transparencia y deshabilitado", "en unas cards crece solo el contenido") y
  pidiera homologar en todo el proyecto. Por eso las convenciones se escriben
  como norma global, no como el arreglo de una pantalla.
- **Paso 2 enmarcado** como los pasos 1 y 3: card dorada de marco delgado
  (`p-2`, separaciones internas del mismo grueso), barra negra con folio +
  badge a la izquierda y botones a la derecha; observaciones y totales de la
  misma altura ("Guardado ✓" es overlay dentro del textarea). La card del paso
  1 se quedó **dorada** — el usuario revirtió el crema ahí.
- **Pills Proveedor/Marca:** Marca es espejo completo de Proveedor
  (`User#brands_in`, `available_brands`/`current_brand`, `PATCH /active-brand`
  con `ActiveBrandsController` validando pertenencia). Sin proveedores ya no
  sale "Proveedor: —". `_supplier_pill` se eliminó al generalizar. Tests en
  `context_pills_test` (4).
- **Encabezado del pedido:** el tipo (Factura/Remisión) solo ofrece lo que el
  cliente tiene en el ERP — sin perfiles fiscales no hay Factura; sin
  remisiones no hay Remisión; con uno solo, tipo fijo sin radio; sin ninguno,
  aviso y no se captura. WhatsApp se eliminó por completo del resumen (vista,
  ruta, acción y asset).
- **Paso 2 — contenido (2026-07-30):** la columna Total de la tabla incluye
  descuento e IVA (`item.total`, como el PDF; antes era cantidad × precio y no
  cuadraba con el Total del pie). La card del encabezado usa los **mismos
  labels** que los combos del paso 1 (RFC — razón social, código —
  descripción del CFDI, sucursal — dirección completa). El buscador de
  producto recibe el foco al entrar. El hub de reportes ganó "← Volver al
  menú" (título arriba de las cards a la izquierda, botón a la derecha).
- **Observaciones siempre en mayúsculas (2026-07-30):** `normalizes` en `Order`
  es la fuente de verdad (el texto viaja al ERP, que maneja mayúsculas) y la
  clase `uppercase` del textarea es solo presentación; el placeholder va
  exento. Lo ya guardado conserva su caja hasta que se edite.
- **Cambiar razón social actualiza el Uso de CFDI (2026-07-30):** controller
  `cfdi-default` con el mapa perfil → uso default del ERP; el `change` del
  combo de razón social clickea la opción del combo de CFDI (reutiliza la
  lógica del select). Sin default configurado, no toca la selección.
- **Reporte de pedidos capturados:** Fecha · Hora (local, separadas) · Cliente
  (clave — nombre) · Vendedor (id — nombre) · Clave local (enlace al pedido) ·
  Renglones · Total · Estatus. El servidor ve además Capturista al inicio.

### Fase C — `rueda-api` export / sync-down (decisiones)

- **Endpoint único:** `GET /ruedas/:id/export` → arma TODO el dataset de la
  rueda en un solo JSON (`RuedaApi::Export.for_rueda`). Acotado a `id_empresa=1`
  y a la rueda. Validado con Oaxaca (`id_rueda=3`): 200, ~3.6 MB, **47 clientes,
  15 vendedores, 3 usuarios, 24 usos CFDI, 18 proveedores, 1 marca, 13,196
  productos**.
- **Llaves del JSON** (las que consumirá el sync-down): `round`, `cfdi_uses`,
  `users`, `salespeople`, `suppliers`, `brands`, `clients` (con `tax_profiles`/
  `receipt_profiles`/`branches` anidados vía `jsonb_agg`), `products` (con
  `supplier_skus` y precio/IVA/tope embebidos). *(Después se sumaron `people`
  —la membresía capturista↔proveedor/marca— y `divide_amounts`: hoy son **10**,
  y el sync-down importa las 10.)*
- **Scope de productos:** unión **marca ∪ proveedor** participante de la rueda
  (`p.id_marca IN marcas` OR `EXISTS com_proveedor_has_producto IN provs`).
- **Scope de clientes:** solo los **registrados en la rueda**
  (`cnf_rueda_negocios_cliente`), no todo el padrón.
- **Precio:** primer renglón vigente de `com_producto_has_precio` (LATERAL,
  `ORDER BY consecutivo LIMIT 1`) → `public_price`/`wholesale_price`/`tax_rate`/
  `max_discount`.
- **`description` del producto = `com_producto.nombre`** (decisión del usuario;
  no `nombre_publico`/`descripcion_corta`). **Unidad = `cnf_unidad_medida.
  abreviacion`** (no existe `clave`).
- **Decimales:** el ERP devuelve NUMERIC como `BigDecimal` y la gema `json` lo
  serializa en notación científica (`"0.47108e3"`). Se resolvía con `deep_coerce`
  → **string decimal plano** (`"471.08"`); rueda-negocios lo castea a `decimal`.
  NO usar Float para montos. (Superado: hoy el cast va en SQL con
  `trim_scale(...)::text` y `deep_coerce` no existe — Grupo B de los BAJA.)
- **`baja = false` en TODO:** los catálogos principales ya filtraban; se agregó
  también en las **7 tablas puente** (`cnf_rueda_negocios_*`,
  `com_proveedor_has_producto`, `com_producto_has_sku`). Sin esto se colaban
  relaciones dadas de baja (p.ej. SKUs muertos en `supplier_skus`).
- **Trampa de validación:** un server viejo (previo a la ruta) puede quedar
  ocupando el puerto → `rackup` nuevo falla el bind silenciosamente y el viejo
  responde 404 al endpoint nuevo. Matar procesos `puma`/`rackup` huérfanos antes
  de probar.

### Fase D — rake `sync:down` en `rueda-negocios` (decisiones)

- **`rake sync:down`** (`lib/tasks/sync.rake`) → `Sync::Down`
  (`app/services/sync/down.rb`). Baja `GET {RUEDA_API_URL}/ruedas/{RUEDA_ID}/export`
  con `Net::HTTP` (stdlib, sin gema nueva) y puebla el Postgres local dentro de
  una transacción. ENV `RUEDA_API_URL` + `RUEDA_ID` en `.env`.
- **Estrategia = REPLACE, no merge** (decisión del usuario). Es un *refresh
  pre-evento*: deja el catálogo local **idéntico al export**. Borra el catálogo
  (hijos→padres, respetando FKs; vacía también las tablas de membresía aún no
  usadas) y reinserta con `insert_all`. Validado: totales en BD == export exacto,
  0 residuo.
- **Guarda:** `Sync::Down::GuardError` si `Order.exists?` → el rake **aborta**
  con mensaje. El sync-down no debe correr sobre pedidos ya capturados (evita
  romper FKs / perder captura). Validado.
- **Usuarios = excepción al replace:** merge por `erp_person_id` **sin tocar
  `role`** + cleanup de capturistas que ya no vienen del ERP. **Nunca borra un
  `server`.**
- **Rol `server` = usuario SEEDEADO** (decisión del usuario, sobre promoción).
  `db/seeds.rb` ahora crea SOLO ese usuario, con identidad sintética
  `erp_person_id = 0` (reservado app; el ERP nunca usa 0) para que el cleanup lo
  preserve siempre. Credenciales por ENV `SEED_SERVER_USERNAME`/
  `SEED_SERVER_PASSWORD` (fallback dev `servidor`/`rueda2026`). El resto del
  dataset (rueda/clientes/productos/capturistas) YA NO se seedea → viene por
  `sync:down`. En dev: `db:reset` (crea server) + `sync:down` (puebla catálogo).
- **Migración `users.prefix`** (`20260725073308`): guarda el prefijo del ERP
  (`cnf_persona.prefijo`, p.ej. "1A") que necesita el folio del sync-up.
  (Superado: el folio lo resuelve `rueda-api` contra el ERP en vivo
  —`prefijo_for`— y la app nunca lee la columna; su destino está en
  `backlog.md`.)
- **SKUs de proveedores fuera de la rueda:** se omiten (no hay proveedor local);
  el rake reporta el conteo. Con Oaxaca: 0 omitidos.
- **`record_timestamps: true`** en `insert_all`/`upsert_all` para que Rails
  llene `created_at`/`updated_at`.

### Fase D — sync-up (alta de pedidos en el ERP) (decisiones)

- **rueda-api `POST /pedidos`** (`RuedaApi::OrderCreate`) inserta en
  `fecego.vta_pedido` + `vta_pedido_detalle` y devuelve `clave_pedido`. Todo en
  una transacción con `pg_advisory_xact_lock(hashtext(prefijo))` para serializar
  la asignación de folio por prefijo.
- **Folio** = prefijo del capturista (`cnf_persona.prefijo` vía `id_persona`) +
  consecutivo (`MAX(substring(clave_pedido FROM 3)::int)+1`, filtrando
  `~ '^[0-9]+$'` para no reventar el cast), a 4 dígitos.
- **Idempotencia:** antes de insertar busca por la PK de negocio
  `(id_empresa, clave_cliente, fecha_pedido, hora_pedido)`; si existe, devuelve
  su folio con `idempotent:true` sin reinsertar. Validado por ambos lados.
- **Defaults de config ESCRITOS** (moda de ~486k pedidos transmitidos; PENDIENTE
  confirmar con FECEGO, se ajustan en `HEADER_DEFAULTS`): `c_FormaPago="99"`,
  `c_MetodoPago="PPD"`, `condicion_pago="50"`, `tipo_precio="MA"`,
  `id_negociaciontipo=1`, `id_enviotipo=1`, `estatus_actual="CAPTUR"`.
  `id_vendedor` = el del cliente; `id_usuario_crea/transmision` = erp_person_id
  del capturista; `transmitido=true`.
- **rueda-negocios `rake sync:up`** (`Sync::Up`): toma `Order.captured` sin
  `erp_folio`, hace POST, y al éxito guarda `erp_folio` + `transmitted_at`
  (columna nueva, migración `20260725153508`). Idempotente: no re-transmite lo
  que ya tiene folio.
- **Hora de captura:** `created_at.localtime` → `fecha_pedido`/`hora_pedido` (el
  ERP maneja horas locales; `created_at` es UTC). Estable → sirve de llave de
  idempotencia.
- **`id_producto` del detalle** = `order_item.product.erp_product_id`.
- **Trampa Sequel:** `Sequel.function(:current_time)` emite `current_time()` con
  paréntesis → error en PG; usar la constante `Sequel::CURRENT_TIME` (y
  `Sequel::CURRENT_DATE`). Y al usar heredoc `<<~SQL` en `DB.fetch`, TODOS los
  args van en la misma línea física del `<<~SQL` o Ruby se los come como cuerpo.
- **Validado end-to-end** contra el ERP dev: pedido factura (cliente ABAISM,
  capturista makita1/prefijo 1A) → folio `1A0016`, cabecera+detalle correctos,
  IVA por partida, totales cuadran; idempotencia confirmada; pedido de prueba
  limpiado del ERP.
- **Bug "no se reflejan en el ERP" (2026-07-30):** comparando nuestros pedidos
  transmitidos (1A0016–1A0020) contra pedidos CAPTUR normales del ERP, columna
  por columna y midiendo invariantes sobre 1.2M de pedidos históricos, nos
  faltaban: **`renglones`** (SIEMPRE = # partidas; nosotros dejábamos 0 — la
  causa más probable), **`id_sucursal_crea=1`**, **`hora_crea` sin
  microsegundos** (los únicos 5 pedidos del histórico con micros eran los
  nuestros; `Sequel::CURRENT_TIME` los incluye → `localtime(0)`) y
  **`observaciones=' '`** cuando viene vacía (moda del ERP). `hora_transmision`
  SÍ lleva micros en el propio ERP — se queda. NO era problema:
  `flujo_recorrido=f` (lo prende un proceso posterior del ERP; pedidos ajenos
  recién capturados también lo traen en `f`) y los campos operativos del
  detalle en 0 vs NULL (el histórico trae ambos). Corregido en
  `OrderCreate.insert_header/insert_details` + UPDATE de remediación a los 5
  pedidos ya transmitidos. Método: **la fila del ERP es la especificación** —
  ante dudas, medir la invariante en el histórico con COUNT.

### Fase D — Panel del servidor (UI de sync) (decisiones)

- **El rol `server` opera el sync desde la UI** (antes solo rakes). Al entrar el
  servidor ve, en el mismo menú (`home#index`, bifurcado por rol), 3 tarjetas:
  **Elegir rueda**, **Obtener información** (sync-down) y **Transmitir pedidos**
  (sync-up) + Reportes. El capturista sigue viendo su menú de captura.
- **Decisiones del usuario:** ejecución en **background job** (no bloquear);
  **tarjetas en el mismo menú** (no panel separado); el `server` es **seedeado**
  (ya existente) y su rol se preserva.
- **rueda-api `GET /ruedas`** (`RuedaApi::Rounds`) — lista las ruedas del ERP
  para elegir cuál trabajar.
- **rueda-negocios:**
  - `Setting` (singleton local): `selected_round_erp_id` + `selected_round_name`
    (guarda el nombre al elegir, para mostrarlo sin depender del sync).
  - `SyncRun` (kind down/up, status running/completed/failed, summary jsonb):
    historial/estado de cada sync. `after_update_commit` hace **broadcast Turbo
    Stream** al stream `"sync_status"` → el menú se actualiza en vivo al terminar
    el job (sin recargar).
  - `Sync::ApiClient` (antes `Sync::Client` — **renombrado** porque `Client`
    colisiona con el modelo dentro de `module Sync`): `list_rounds`,
    `fetch_export`. Reusado por rake y jobs.
  - Jobs `SyncDownJob` / `SyncUpJob`: crean/cierran el `SyncRun`, corren
    `Sync::Down`/`Sync::Up`. `solid_queue` en prod (corre dentro de Puma con
    `SOLID_QUEUE_IN_PUMA`); `async` en dev.
  - Guarda `require_server` + `ServerController` (rounds, select_round,
    sync_down, sync_up). Evita disparar un sync si ya hay uno `running`.
- **Corridas huérfanas (2026-07-28):** un `SyncRun` nace `running` y solo el job
  lo cierra; si el proceso muere a media corrida (apagón, cierre de `bin/dev` —
  con el adapter de jobs en proceso el job no sobrevive), el renglón queda
  `running` para siempre: el panel gira "en progreso" eterno y la guarda bloquea
  nuevas corridas. Le pasó al usuario en la laptop y ni el reinicio lo curaba.
  Fix: `SyncRun.recover_orphaned!` desde
  `config/initializers/sync_run_recovery.rb`, dentro de
  `Rails.application.server { }`. Validado con un server efímero que barrió al
  huérfano sembrado, y el runner que lo sembró no lo tocó. (La norma
  generalizada quedó en `docs/convenciones-codigo.md`.)
- **Con pedidos que solo viven en la laptop no se sincroniza ni se cierra la
  rueda (2026-08-10).** Regla única en `Sync::Guards`, con dos guardas:
  - `no_draft_orders!` (sync-**up**): solo los borradores estorban.
  - `no_local_orders!(error, accion)` (sync-**down** y **cerrar rueda**): las
    dos operaciones borran TODOS los pedidos locales, así que bloquean por
    borradores **y** por finalizados sin transmitir. `accion` completa la
    frase ("al obtener la información" / "al cerrar la rueda") — es lo único
    que cambia entre ambas. Los transmitidos nunca bloquean: ya viven en el
    ERP.
  - **sync-up:** solo toma `captured`, así que el borrador no se transmitiría
    y el operador creería que ya todo llegó al ERP.
  - **sync-down:** su replace hace `Order.destroy_all` — el borrador se
    **borraba en silencio**. Antes NO bloqueaba (decisión original: el
    sync-down es de oficina, antes del evento, con nadie capturando); se
    cambió porque el modelo de operación es laptop-servidor **en el evento**,
    en la misma LAN, y entre días de una rueda el escenario "descargar
    mientras alguien captura" pasó de imposible a plausible. Hubo que
    reescribir el test que fijaba lo contrario.
  - En `Down.guard!` los borradores se revisan **antes** que los capturados
    sin transmitir: son el prerrequisito del prerrequisito (con borradores
    vivos tampoco se puede transmitir, así que avisar primero de los
    pendientes mandaría al operador a un botón que también lo rechazaría).
  - El mensaje completo vive en la guarda (los controladores solo hacen
    `alert: e.message`); antes el controlador le concatenaba la acción.
  - **El sync-down avisa de ambos casos de una vez** ("Hay 2 pedidos en
    borrador y 3 sin transmitir; se perderían al obtener la información. Pide
    que terminen o descarten los borradores, transmite los demás, y vuelve a
    intentar"). El orden de solución está forzado, pero en un evento el
    operador necesita ver el camino completo desde el primer intento para
    organizar a su gente, no descubrirlo de mensaje en mensaje.
- **Lenguaje de los mensajes al usuario (regla del usuario, 2026-08-10): sin
  vocabulario técnico.** Quien los lee está en el evento resolviendo un
  problema, no depurando el sistema. Barrido en los avisos del panel:
  "corrida de sync en curso" → "Se está obteniendo información o transmitiendo
  pedidos"; "el replace purga los pedidos locales" → "se perderían al obtener
  la información"; "Descarga iniciada" → "Obteniendo la información";
  "N pedido(s) locales eliminados" → "Se eliminaron N pedidos de esta laptop".
  Los mensajes **concuerdan en número** (`Guards.pedidos/lo/perderia/
  transmitelo`): un "se perderían 1 pedido" delata descuido justo cuando el
  operador necesita confiar en lo que lee. Los detalles técnicos de fallas de
  API (p.ej. "respuesta sin clave_pedido") se conservan: son diagnóstico, no
  instrucción, y van al panel/log.
- **Detalle de la guarda del sync-up:** tres puntos de llamada: el
  **controlador** (antes de crear el `SyncRun`, para que una condición previa
  no quede registrada como corrida fallida), `run!` (cubre `rake sync:up`, que
  aborta legible) y el **job** (solo por carrera: un borrador creado entre el
  pre-chequeo y el arranque).
  - **Criterio de UI decidido por el usuario:** sigue el patrón de "Cerrar
    rueda" — la card NO se bloquea, el modal de confirmación aparece normal y
    el motivo se avisa en el **toast al confirmar**. (Se propuso bloquear la
    card como hace "Elegir rueda" con rueda en curso; el usuario prefirió el
    aviso.) Nota: hoy el menú mezcla ambos criterios — las condiciones de sync
    (corrida viva) se muestran bloqueando la card, y las de datos (pedidos
    pendientes) solo avisan al confirmar.
  - **Riesgo operativo — ver "Próximos pasos":** con las tres operaciones
    bloqueadas, un borrador abandonado (capturista que se fue, tablet muerta)
    deja la laptop **atorada**: no se transmite, no se obtiene información y
    tampoco se cierra la rueda. El escape hoy es parcial: el reporte "Pedidos
    capturados" muestra `Order.all` para el rol servidor, así que el operador
    ve cuáles están en borrador y de quién son, pero **no puede descartarlos
    él mismo**. El usuario lo dio por dentro del alcance, a resolver después.
  - **Homologado el mismo día:** "Obtener información" tenía el mismo hueco —
    con pedidos capturados sin transmitir creaba el `SyncRun`, el job reventaba
    con `Down::GuardError` y quedaba una **corrida fallida** (y sucia la card
    de "última descarga") por una condición previa que nunca se intentó.
    `Sync::Down#guard!` (privado de instancia, sin estado del objeto) pasó a
    ser `Sync::Down.guard!` de clase y `ServerController#sync_down` lo llama
    antes de crear el run, con `rescue` → toast. El job conserva su rescue como
    red para la carrera. **Los tres botones del panel quedan con el mismo
    trato:** condición no cumplida se avisa al confirmar, sin registrar
    corridas que no ocurrieron.
- **Validado end-to-end en el navegador** (rueda-negocios en :3001 con
  `RUEDA_API_URL`, rueda-api en :4568): login server → elegir Oaxaca → obtener
  información (job → "✓ Listo · 13,196 productos…" vía Turbo Stream) → transmitir
  (job → "✓ Listo · 0 pedidos").
- **Trampa de layout:** `turbo_stream_from` renderiza un
  `<turbo-cable-stream-source>` que, si cae dentro de un grid, cuenta como celda
  y descuadra el layout. Va FUERA del grid (en `home/index`, antes de la barra);
  el partial del menú server es un solo `<div>` (la columna derecha), igual que
  el del capturista. Las cards usan un **grid de columnas fijas**
  (`grid-cols-[3.5rem_11rem_minmax(0,1fr)]`: icono·título·desc) para alinear
  título/descripción entre sí pese a mezclar `link_to` y `button_to` (el `<form>`
  del button descuadra un layout basado en `flex`). Íconos Heroicons (outline),
  coloreados con `currentColor` según la card.
- **Trampa:** `allow_browser versions: :modern` (ApplicationController) bloquea
  con 403 las sesiones de `ActionDispatch::Integration` (UA no reconocido) — no
  es bug; validar la UI con navegador real o request specs con UA moderno.

### Estatus del pedido — captured / transmitted (decisiones)

- **Enum `status` = `draft → captured → transmitted`** (reemplaza `submitted`).
  `draft`=Borrador (en captura), `captured`=Capturado (finalizado por el
  capturista, **editable**), `transmitted`=Transmitido (ya en el ERP, **NO
  editable**). Migración de datos `20260725184048` (submitted→captured; y
  →transmitted si tenía erp_folio).
- **`Order#submit!` → `capture!`** (pone `status: captured`). El botón del paso 2
  (`orders/show`) dice **"Guardar"** (antes "Enviar"); mensajes ajustados.
- **`capture` sigue editable hasta transmitir** (decisión del usuario); solo
  `transmitted` bloquea. `Order#editable? = !transmitted?`.
- **Bloqueo de edición** (backend + UI): `OrderItemsController` before_action
  `ensure_editable` (403) y guardas en `orders#capture`/`observations`. En
  `orders/show`, si no es editable se ocultan buscador, controles de partida
  (cantidad/descuento/borrar → texto plano) y observaciones (solo lectura);
  acciones = solo "Ver PDF" + "Volver al menú".
- **Transmisión (sync-up):** selecciona `Order.captured.where(erp_folio: nil)` y
  al transmitir pone `status: "transmitted"` (+ `erp_folio` + `transmitted_at`).
- **Etiquetas** (`Order#status_label` = Borrador/Capturado/Transmitido) usadas en
  el reporte (badge de color por estado), el PDF (`Estatus:` + `Transmitido:`
  usa `transmitted_at`) y `orders/show`.
- Validado en navegador: captura muestra "Guardar"/"Capturado" editable;
  transmitido queda de solo lectura.

