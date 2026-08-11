# Cómo se audita este proyecto

Método de las auditorías de `rueda-negocios` + `rueda-api`, para poder repetirlo
sin depender de quién lo corrió la vez pasada. Los resultados de cada auditoría
se publican aparte (ver "Historial" al final).

## El método en una frase

**Cinco revisiones independientes en paralelo, una por dimensión, y después una
segunda pasada donde cada hallazgo grave se reproduce contra el código en
ejecución antes de publicarlo.**

Esa segunda pasada es lo que separa un reporte útil de una lista de sospechas:
en la 3ª auditoría varios "hallazgos" no la sobrevivieron. Un reporte corto y
cierto vale más que uno largo y especulativo.

## Reglas que hacen que rinda

- **Acotar el alcance** al código nuevo desde la auditoría anterior
  (`git log --since=<fecha>`), sin prohibir reportar algo grave que quede fuera.
- **Revisiones independientes:** cada dimensión trabaja sin ver lo que
  encontraron las demás. Los duplicados se consolidan al final; el sesgo
  compartido es peor que la redundancia.
- **Decir explícitamente qué NO reportar.** Lo diferido por decisión (HTTPS,
  tokens, throttling — ver `backlog.md`) llena el reporte de ruido conocido si
  no se excluye.
- **Exigir escenario de falla concreto**, no juicios de estilo: qué input o qué
  secuencia produce el resultado incorrecto, y cuál sería el correcto.
- **Las afirmaciones sobre interacción se prueban con clics reales.** Los
  eventos sintéticos no reprodujeron el bug del calendario de rango (el DOM se
  reconstruía bajo el cursor y Stimulus enlaza las acciones de los nodos nuevos
  de forma asíncrona).
- **Verificar antes de publicar.** Reproducir en consola, en la BD o en el
  navegador. Lo que no se sostenga, va a una sección de "descartados" con una
  línea — también es información.
- **Severidad honesta:** ALTA = corrompe datos, bloquea la operación sin salida
  o expone información. Si todo es alto, nada lo es.

## Las cinco dimensiones

### 1. Seguridad
Autorización y alcance por rol (que un capturista no llegue a datos ajenos ni
forzando parámetros), IDOR, inyección SQL —con atención al SQL crudo—, XSS,
CSRF, manejo de sesión, mass assignment, y exposición de datos en respuestas,
mensajes de error o logs.

### 2. Calidad y corrección
Casos borde (pedidos sin partidas, filtros combinados, rangos invertidos,
husos horarios), consistencia entre cálculos equivalentes —el agregado en SQL
contra el cálculo en Ruby—, N+1, transacciones y carreras, manejo de errores
que deje estado a medias, y **huecos de cobertura de pruebas**: qué
comportamiento importante no está probado y por qué importa.

### 3. Documentación contra código
Afirmaciones falsas, referencias fantasma, reglas de `docs/convenciones-*.md`
que el código viola, renglones del backlog que ya se implementaron, y
decisiones registradas en `memory.md` que después se revirtieron sin dejar nota.

### 4. Usabilidad y accesibilidad
Con el contexto de uso como vara: salón lleno, prisa, capturistas en **tablet**
y equipo-servidor en laptop, sin internet. Callejones sin salida, estados
vacíos y de error (¿dicen qué pasó y qué hacer?), objetivos táctiles y gestos
que no existen en pantalla táctil, foco y navegación por teclado, consistencia
entre pantallas equivalentes, y trabajo repetitivo en captura seguida.

### 5. Convenciones y consistencia
Adherencia a `docs/convenciones-visuales.md` y `docs/convenciones-codigo.md`,
dos formas distintas de resolver lo mismo, idiomática Rails, nomenclatura,
comentarios que ya no describen su código, y rubocop.

## Dimensiones propuestas (aún no aplicadas)

Fundadas en un dato incómodo del historial: **los defectos más caros del
proyecto los encontró el usuario usando el sistema, no las auditorías.**

### 6. Fidelidad con el ERP
La familia de bugs más costosa fue de contrato con el ERP y ninguna auditoría
detectó uno: `renglones = 0` (los pedidos no se reflejaban en las pantallas del
ERP), `hora_crea` con microsegundos, `id_proveedor = 0` sin `NULLIF` (se perdían
las membresías solo-marca), el código a 6 dígitos, el empaque mínimo.

Todos comparten forma: **escribimos o leemos algo que el ERP interpreta
distinto, y nada revienta** — el dato simplemente queda mal. Las cinco
dimensiones actuales no lo ven, porque el código es coherente consigo mismo y
con nuestra documentación; el desacuerdo está del otro lado del contrato.

Método que sí funcionó: comparar nuestra fila contra una fila **nativa** del
ERP columna por columna, y **medir la invariante contra el histórico real**
(`SELECT count(*) … WHERE <invariante no se cumple>`) en vez de suponerla.

### 7. Operación y recuperación
El sistema es *una laptop haciendo de servidor en un salón*: sus peores fallas
son operativas. De ahí salieron el `SyncRun` huérfano que dejaba el panel
girando para siempre, la carrera entre descargar y transmitir que perdía el
folio del ERP, y el barrido de huérfanos que en producción mataría corridas
vivas.

Qué enumeraría: puntos donde el proceso puede morir (apagón, reinicio, cierre
del servidor), concurrencia entre operaciones del panel, idempotencia de los
reintentos, y **en qué estado queda el operador tras cada falla — incluida la
pregunta de si le queda salida**.

Con siete dimensiones el costo sube. Si hay que elegir, la 6 tiene el
rendimiento histórico demostrado; la 7 gana urgencia conforme se acerca el
evento real.

## Historial

- **1ª (2026-07-25)** — 6 ALTA · 18 MEDIA · 14 BAJA → remediada al 100%.
- **2ª (2026-07-26, post-remediación)** — 2 ALTA · 9 MEDIA · 24 BAJA →
  remediada al 100%; B23 y B24 quedaron como registro sin acción.
- **3ª (2026-08-10)** — 3 ALTA · 11 MEDIA · 9 BAJA · 0 vulnerabilidades →
  remediada al 100% el mismo día.

El detalle de las dos primeras está en `docs/auditorias-2026-07.md`; el de la
tercera, en la sección "3ª auditoría — remediación" de `memory.md`. Los
reportes completos se publicaron como artifacts (las URLs las tiene el
usuario).
