# Convenciones visuales y de texto

Normas que rigen **toda** pantalla nueva o modificada. Se cargan en contexto
desde `CLAUDE.md`. El relato de cómo se llegó a cada una vive en `memory.md`.

## Shell y layout

- **Shell único** en todas las pantallas: fondo negro + patrón de herramientas
  al 0.18 + `shared/_top_bar` (logo → menú, pill Usuario, pills de contexto,
  Cerrar sesión con modal). El título de la pantalla va en el cuerpo, no en la
  barra. Margen lateral **5%**.
- Superficies de contenido en **card**, con barra negra de título cuando la
  pantalla tiene acciones (folio/estatus a la izquierda, botones a la derecha).
- **El regreso va en la fila del título de la pantalla**, alineado a la
  derecha, y es **uno solo**: "← Volver a …" con `back_link_class`
  (`bg-white/10`, más ligero que un botón de acción — es navegación, no
  acción). Nunca dentro de la barra negra de la card, que es solo para
  acciones. El helper existe para que el estándar tenga un único lugar donde
  cambiarlo: cuando estaba copiado en cada vista, el detalle del pedido se
  desvió al estilo de acción y nadie lo notó.

## Roles por color

| Color | Uso |
|---|---|
| Dorado | Navegación y acciones (cards de menú, botones, badge Capturado) |
| Crema | **Toda** superficie de contenido, fija o flotante (tablas, forms, totales, dropdowns, avisos) |
| Negro | Controles de captura (buscadores, selects, `thead`) y barras de título |
| Coral | Acción primaria o culminación (Guardar, Subtotal, flama disponible, badge Transmitido) |
| Rojo | **Solo** error: flash de alerta (`red-700`), anillos de campo faltante, motivos de falla del panel |
| Neutral-700 | Acción secundaria o destructiva-con-modal (Editar, Descartar, Cancelar, Cerrar rueda) |
| Emerald | **Solo** feedback global (flash, "✓ Listo" del sync) |
| Blanco | **Solo** campos de entrada — es la señal de "esto se escribe" |

**El umbral depende de si el elemento es texto o gráfico, y es fácil aplicar el
equivocado.** AA pide 4.5:1 para texto normal y 3:1 para gráficos y texto
grande (≥18.66 px, o ≥14 px en negrita solo si además es grande). El coral
#bd5343 sobre crema da 4.04:1: alcanza para un ícono, **no** para un porcentaje
a 14 px — ahí va `brand-coral-dark` (5.06:1). Medir antes, y decir contra qué
vara (7ª auditoría).

El coral es **#bd5343**, no el #ce6150 original: con blanco encima daba 3.85:1,
debajo del 4.5 que pide AA para texto normal — y ahí viven los botones de
confirmación de todos los modales y los avisos de error del paso 1, los que
explican qué falta. Tablet en un salón con ventanal es el caso real. Por la
misma regla el flash de alerta es `red-700` (~6:1), no `red-600` (4.08:1).
Cualquier tono nuevo que lleve texto blanco encima se mide antes de usarse.

Grises del manual de identidad: `neutral-400` para el fondo de controles
grises (buscador de producto), con texto e íconos `neutral-700/900`.

**El dorado no sirve de trazo sobre el crema: da 1.39:1.** Si un ícono dorado
tuviera que llamar la atención dentro de una card, tendría que ir de
superficie, no de trazo.

En la práctica no hizo falta: el ícono que más debe llamar la atención de la
tabla —la flama de promoción "disponible"— va en **coral de superficie**
(píldora rellena, ícono blanco), el mismo tono del botón primario y del
renglón Subtotal, que es lo que el ojo ya busca en esa pantalla. Blanco sobre
coral da 4.69:1 y coral sobre crema 4.04:1.

**Un estado no se distingue solo por el matiz.** Los tres de la flama se
separan por FORMA: píldora rellena (disponible) · trazo coral (aplicada) ·
trazo `neutral-600` (en reposo, el tono ya validado sobre crema). Con solo
color, "aplicada" y "en reposo" compartían silueta y su contraste entre sí era
de 1.67:1 — y en deuteranopía (Viénot 1999) esos dos trazos quedan a **1.96:1**
entre sí, o sea que la distinción se pierde casi por completo. Toda cifra de
simulación va con el modelo y con el par medido: el "2.31:1" que decía antes
esta línea no se reproduce con ninguna lectura, y sin decir contra qué
superficie era imposible comprobarlo (8ª auditoría).

**`bg-white/10` es para fondo OSCURO, no para el marco dorado de los filtros.**
Un botón secundario con esa clase dentro de la barra dorada se lava hasta
volverse ilegible — el blanco sobre dorado claro no tiene dónde apoyarse. Ahí
el secundario va con el mismo negro de los controles (`control_class`), que ya
es el fondo de los combos vecinos. Pasó con el "Limpiar" del reporte de
productos y solo se vio al mirar la pantalla renderizada.

**Una columna que ES el reporte no se oculta en tablet.** `hidden
lg:table-cell` está bien para datos secundarios —la hora o el vendedor del
reporte de pedidos—, pero en una tabla cuyas columnas son lo que el usuario
pidió ver, esconderlas deja media pantalla inservible en la tablet del evento.
La salida es dar `min-w` a la columna larga y dejar que el contenedor
`overflow-x-auto` haga su trabajo: se llega a todo con scroll, y la descripción
no se estrangula a cinco líneas.

**Nada de paneles translúcidos** (`bg-white/5`, `bg-white/10`) como superficie
de contenido: sobre el shell negro con patrón se lavan y el bloque "no se
aprecia". Un bloque de contenido es crema; si necesita jerarquía propia, se
enmarca con la gramática de card: marco dorado delgado (`p-2`) + barra negra
de título + cuerpo crema. El `bg-white/10` queda solo para botones
secundarios sobre fondo oscuro.

## Iconografía

**100% Heroicons outline**, `currentColor`, trazo 1.5. Cero emojis y cero
assets de íconos sueltos.

**Excepción: la flecha de orden de una tabla** (`sort_caret`). Va a **trazo 2**
y no 1.5: es un chevron de 16 px (`h-4`) sobre el `thead` negro, y a ese tamaño
el trazo fino se pierde justo en el elemento que dice cuál columna manda. Mismo
argumento que el favicon —a tamaño chico el trazo desaparece— y por eso queda
escrito aquí: la del favicon estaba registrada y esta no, así que parecía un
descuido (9ª auditoría).

**Excepción: el favicon** (`public/icon.svg` + `icon.png`). Va en silueta
**sólida**, no en outline: a 16 px un trazo de 1.5 desaparece. Y el dorado va
de **fondo**, no de acento — entre varias pestañas abiertas el color identifica
antes que la forma. Cualquier ícono nuevo que se vea a ese tamaño se juzga
renderizándolo a 16 px, no a 256.

## Hover, transformaciones y modales

- El hover **escala la card visible completa** (`hover:scale-[1.015]`), nunca
  el botón interno.
- **El diálogo de un modal va FUERA del nodo que se transforma:** un
  `transform` en cualquier ancestro rompe el `position: fixed` del overlay. En
  las cards con modal, el contenedor `data-controller="modal"` queda como
  wrapper neutro, la card visible es un div interno que escala, y el diálogo
  cuelga del wrapper.
- **Wrappers hermanos con el mismo z-index se tapan entre sí.** El `z-50` del
  diálogo solo cuenta DENTRO de su contexto de apilamiento, así que si la
  página se parte en dos `relative z-10` hermanos (header con modal +
  contenido), el contenido gana por estar después en el DOM y esconde el
  modal. El wrapper que contiene un modal va **`z-20`**.
- Las cards bloqueadas **no** escalan (llevan `opacity-60` en su lugar). Pills
  y botones chicos usan hover de color, no de escala.

## Validar la UI es ejercitar la TRANSICIÓN, no mirar el estado final

Una captura de pantalla dice que el estado A y el estado B se ven bien; los
defectos viven en el camino entre los dos, y en los bordes del layout. En este
proyecto los encontró el usuario, no las pruebas ni la revisión visual:

- Un botón que cambia de forma y de color a la vez parpadeaba y dejaba un
  cuadro, porque `transition-colors` anima el color pero **no** el
  `border-radius`, y `animate-pulse` deja la opacidad a media animación al
  quitarse. Solo se ve durante los ~150 ms del cambio.
- Un dropdown se cortaba **solo en el último campo del formulario**, donde ya
  no hay página que crecer debajo.
- Una columna nueva rompía el ancho **solo en tablet vertical y con una partida
  del genérico**, que fuerza otra columna visible.

Por eso, al terminar una pantalla: recorrer los cambios de estado con el
elemento a la vista, abrir las capas flotantes en el **último** campo y con la
lista más larga, y mirarlo a 768 px además de en la laptop.

## Bloqueado por regla de negocio ≠ deshabilitado

Una fila que una regla congela (hoy: partida con promoción aplicada) no usa
`disabled` ni el 60%: **sustituye sus campos por texto**, como una fila ya
transmitida, y se tiñe con `bg-black/[0.04]`. Ese tinte da 1.10:1 sobre crema
— es un matiz, no una señal —, así que el motivo va escrito en un **badge en la
fila** (`neutral-700`, junto a la descripción). El texto largo que explica la
regla vive en su modal, pero el capturista que va a corregir una cantidad
necesita el motivo donde choca con el problema (7ª auditoría).

## Los importes van a la derecha

En toda tabla: precio unitario y total alineados a la derecha con
`tabular-nums`, para que las comas decimales queden en columna entre renglones.
Cantidad y descuento van centrados — no son importes. Es lo que el PDF ya hacía.

## Deshabilitado = 60%

Todo elemento deshabilitado o "próximamente" se ve al **60%**:

- **Con badge** ("Próximamente"): fondo con alpha (`bg-*/60`) + contenido
  `opacity-60` + badge dorado a plena opacidad.
- **Sin badge** (bloqueo por estado): `opacity-60` en el contenedor completo.
- Cuando dentro del bloque hay información que el usuario necesita leer justo
  en ese momento (p. ej. el contador de partidas al llegar al tope), el 60% se
  aplica solo al **control**, no al dato. Incluye el **placeholder** cuando al
  deshabilitarse pasa a explicar *por qué* no se puede escribir: atenuarlo lo
  dejaba en 2.21:1, y no se arregla oscureciéndolo — ni `neutral-900` al 60%
  llega a 4.5.

No usar `opacity-50` ni `disabled:opacity-*`. El atributo `disabled` del botón
sí se conserva: es comportamiento, no estética.

## Pills de contexto

Partial genérico `shared/_context_pill`, con la misma dinámica para cualquier
dimensión (proveedor, marca): **0 → oculto · 1 → estático · varias →
selector** que cambia el activo de sesión. Son etiqueta de contexto: no
restringen la captura.

El panel del combo necesita `w-max + right-0 + whitespace-nowrap`: como es
absoluto, dimensiona contra el pill (angosto) y parte los nombres en varias
líneas.

## Textos al usuario

- **Sin vocabulario técnico.** Quien los lee está en el evento resolviendo un
  problema, no depurando el sistema: "se perderían al obtener la información",
  no "el replace purga los pedidos locales". Los comentarios de código sí
  llevan el término técnico; el corte es la frontera de la pantalla.
- **Concordancia de número** siempre (1 pedido / 2 pedidos, se perdería / se
  perderían). Nada de `pedido(s)`.
- El mensaje dice **qué pasó y qué hacer**. Si el camino tiene varios pasos, se
  enuncian todos de una vez en vez de irlos revelando de error en error.
- Los detalles técnicos de fallas (respuestas rotas de la API, excepciones) sí
  se conservan donde son **diagnóstico y no instrucción**: panel de corridas y
  log.
