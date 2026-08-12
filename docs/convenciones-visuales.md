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
| Coral | Acción primaria o culminación (Finalizar, Total, badge Transmitido) |

El coral es **#bd5343**, no el #ce6150 original: con blanco encima daba 3.85:1,
debajo del 4.5 que pide AA para texto normal — y ahí viven los botones de
confirmación de todos los modales y los avisos de error del paso 1, los que
explican qué falta. Tablet en un salón con ventanal es el caso real. Cualquier
tono nuevo que lleve texto blanco encima se mide antes de usarse.
| Emerald | **Solo** feedback global (flash, "✓ Listo" del sync) |
| Blanco | **Solo** campos de entrada — es la señal de "esto se escribe" |

Grises del manual de identidad: `neutral-400` para el fondo de controles
grises (buscador de producto), con texto e íconos `neutral-700/900`.

**Nada de paneles translúcidos** (`bg-white/5`, `bg-white/10`) como superficie
de contenido: sobre el shell negro con patrón se lavan y el bloque "no se
aprecia". Un bloque de contenido es crema; si necesita jerarquía propia, se
enmarca con la gramática de card: marco dorado delgado (`p-2`) + barra negra
de título + cuerpo crema. El `bg-white/10` queda solo para botones
secundarios sobre fondo oscuro.

## Iconografía

**100% Heroicons outline**, `currentColor`, trazo 1.5. Cero emojis y cero
assets de íconos sueltos.

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
