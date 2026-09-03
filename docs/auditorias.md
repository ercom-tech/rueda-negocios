# Cómo se audita este proyecto

Método de las auditorías de `rueda-negocios` + `rueda-api`, para poder repetirlo
sin depender de quién lo corrió la vez pasada. Los resultados de cada auditoría
se publican aparte (ver "Historial" al final).

## El método en una frase

**Una revisión independiente por dimensión, todas en paralelo, y después una
pasada de verificación adversarial donde cada hallazgo grave se intenta REFUTAR
contra el código en ejecución antes de publicarlo.**

Cuántas dimensiones se lanzan depende del alcance: el proyecto completo las
usa todas; un lote de cuatro commits se auditó con cuatro (8ª) y el de la 9ª
con cinco. Menos auditores sobre poco código rinde más que nueve mirando lo
mismo.

Esa segunda pasada es lo que separa un reporte útil de una lista de sospechas,
y su historial lo demuestra: en la 3ª varios "hallazgos" no la sobrevivieron;
en la 4ª degradó 5 de 6 ALTA y refutó el sexto; en la 5ª degradó 6 MEDIA,
retiró un hallazgo completo y les encontró agravantes a los confirmados. Un
reporte corto y cierto vale más que uno largo y especulativo.

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
  línea — también es información. El verificador trabaja con mandato de
  **refutar**, no de confirmar.
- **Toda medición dice sobre qué RECORTE se hizo** (qué tabla, qué filtro, qué
  rama del código). En la 4ª, un ALTA se refutó porque midió la rama de
  *sucursal* del ERP cuando nuestros pedidos entran por la de *persona*; en la
  5ª, validar el recorte antes que las cifras evitó repetir el error.
- **Toda cifra que se ESCRIBE lleva su recorte al lado, no solo las que se
  miden durante la auditoría.** En la 8ª, la mayoría de los hallazgos de
  documentación fueron números que yo mismo había puesto en comentarios y en el
  backlog sin decir de dónde salían: un "19.84% de las facturas" que eran todos
  los comprobantes, un "9 de cada 10" que solo vale para las 1,000 palabras más
  frecuentes, dos tiempos en milisegundos que no se reproducen. Ninguno cambia
  una decisión, y todos costaron medirse otra vez.
- **Una cifra correcta no protege de una conclusión equivocada.** El caso de
  `dividir_facturas`: la medición era buena y ya decía lo contrario de lo que
  se concluyó encima de ella. Cuando algo resulte estar mal, la primera
  pregunta no es "¿qué recorte falló?" sino "¿la conclusión se sigue del dato?"
  — si se registra como error de medición, la próxima auditoría re-mide algo
  que estaba bien y no revisa el razonamiento, que es lo que falló.
- **Antes de tocar una pantalla, releer las convenciones que la rigen.** En la
  9ª, cuatro hallazgos independientes fueron la misma regla ya escrita sin
  aplicar: "el orden sigue a lo que la celda muestra" (roto en dos columnas),
  "el dorado no sirve de trazo sobre el crema" (propagado a una pantalla nueva)
  y el saneo de `id_param` (reescrito con `to_i`). Una de ellas tenía **dos
  días** de escrita. El fallo no es de memoria sino de encaje: la regla estaba
  archivada bajo "columnas calculadas" y el caso nuevo era "columna que muestra
  otro campo".
- **Verificar las cifras del propio auditor antes de escribirlas.** En la 9ª se
  re-midieron las tres principales y las tres reprodujeron — pero el ejercicio
  vale igual: es lo que separa "un agente lo dijo" de "está medido", y en la 8ª
  un auditor llegó a citar una tabla vacía por confundir dos esquemas.
- **Severidad honesta:** ALTA = corrompe datos, bloquea la operación sin salida
  o expone información. Si todo es alto, nada lo es.
- **Un defecto puede ser viejo y aun así ser culpa del cambio nuevo.** El PDF
  sin totales llevaba siete auditorías vivo, pero los regalos —introducidos en
  el lote auditado— multiplican por 5 los renglones de doble alto y lo vuelven
  mucho más probable. Preguntar por lo que el código nuevo hace más FRECUENTE,
  no solo por lo que rompe.

## Las dimensiones

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

### 6. Fidelidad con el ERP
Nació de un dato incómodo: la familia de bugs más costosa fue de contrato con
el ERP y ninguna de las cinco dimensiones clásicas detectó uno (`renglones =
0`, `hora_crea` con microsegundos, `id_proveedor = 0` sin `NULLIF`, el código
a 6 dígitos, el empaque mínimo). Todos comparten forma: **escribimos o leemos
algo que el ERP interpreta distinto, y nada revienta** — el dato simplemente
queda mal, porque el código es coherente consigo mismo y con nuestra
documentación; el desacuerdo está del otro lado del contrato.

Método: comparar nuestra fila contra una fila **nativa** del ERP columna por
columna, y **medir la invariante contra el histórico real** (`SELECT count(*)
… WHERE <invariante no se cumple>`) en vez de suponerla — siempre sobre el
recorte por el que de verdad operamos (rama de persona,
`id_sucursal_crea = 1`). Estrenada en la 4ª, produjo su único ALTA; en la 5ª,
el hallazgo del redondeo del encabezado.

### 7. Operación y recuperación
El sistema es *una laptop haciendo de servidor en un salón*: sus peores fallas
son operativas. Enumera: puntos donde el proceso puede morir (apagón,
reinicio, Ctrl-C, kill), concurrencia entre operaciones del panel y con la
captura, idempotencia de los reintentos, y **en qué estado queda el operador
tras cada falla — incluida la pregunta de si le queda salida y de si alguna
pantalla se la dice**. Estrenada en la 4ª; en la 5ª produjo el único ALTA (el
pedido duplicado en el ERP guiado por el propio mensaje de colisión).

### 8. Textos de los caminos de falla
Estrenada en la 6ª, donde encontró los 2 ALTA. No revisa la pantalla feliz sino
**lo que el sistema dice cuando algo sale a medias**: el mensaje nombra lo que
de verdad pasó, dice qué hacer, enuncia todos los pasos de una vez en vez de
irlos revelando de error en error, concuerda en número, y no usa vocabulario
técnico (ver `docs/convenciones-visuales.md`). El peor caso que buscó —y
encontró— es el mensaje que **guía al operador hacia el daño**: el aviso de
colisión que lo mandaba a reintentar y duplicaba el pedido en el ERP.

### 9. Riesgo de despliegue
Se estrena en la 9ª, cuando el encargo fue auditar **lo pendiente de subir a la
laptop**, y produjo tres ALTA por sí sola. Pregunta: qué necesita el lote para
desplegarse (gemas, migraciones, initializers, clases de Tailwind, variables),
**qué se rompe si falta cada paso y con qué síntoma lo ve el operador**, qué
pasa si se despliega a medias o en mal orden entre repos, si la reversión deja
la app funcionando, y si la guía escrita sigue siendo cierta.

Rinde porque mira el software como algo que hay que **instalar**, no solo
ejecutar: los dos ALTA principales —sin `bundle install` la app no arranca; sin
`restart` los initializers nuevos no existen— no son defectos del código y
ninguna otra dimensión los habría buscado.

## Historial

- **9ª (2026-09-02)** — alcance: **lo pendiente de desplegar en la laptop**
  (`bba5265..HEAD`, 5 commits, 34 archivos), con 5 auditores, uno de ellos la
  dimensión nueva de despliegue — **6 ALTA · ~18 MEDIA · ~28 BAJA** →
  **remediada al 100% en siete bloques** (detalle en "9ª auditoría —
  remediación" de `memory.md`). Patrón que dejó: **cuatro hallazgos
  independientes fueron la MISMA regla, ya escrita en el repo, sin aplicar** —
  y tres de esas reglas se habían escrito en los días anteriores. Tener la
  norma no basta si el caso nuevo no se parece al que la motivó.

- **8ª (2026-08-24)** — solo lo posterior a la 7ª (4 commits, 23 archivos), con
  4 auditores en vez de 8 por el alcance chico — 1 **CRÍTICA** · 5 ALTA ·
  7 MEDIA · 10 BAJA · 1 degradado (ALTA→BAJA) → **remediada al 100% el mismo
  ciclo**. La CRÍTICA (el PDF sin totales) era **preexistente** y se le había
  pasado por encima a siete auditorías: nació de mirar el PDF por su texto
  extraído, que no distingue "está en el documento" de "está en la hoja
  correcta". Patrón que dejó: **el riesgo no estaba en el código nuevo sino en
  lo que el código nuevo hacía más probable** (los regalos multiplican por 5
  los renglones de doble alto y empujan a la franja mala), y **las cifras que
  yo mismo escribí sin declarar su recorte** fueron la fuente de más hallazgos
  que cualquier defecto de lógica.

- **1ª (2026-07-25)** — 6 ALTA · 18 MEDIA · 14 BAJA → remediada al 100%.
- **2ª (2026-07-26, post-remediación)** — 2 ALTA · 9 MEDIA · 24 BAJA →
  remediada al 100%; B23 y B24 quedaron como registro sin acción.
- **3ª (2026-08-10)** — 3 ALTA · 11 MEDIA · 9 BAJA · 0 vulnerabilidades →
  remediada al 100% el mismo día.
- **4ª (2026-08-11)** — primera con 7 dimensiones — 1 ALTA · 37 MEDIA ·
  31 BAJA · 0 vulnerabilidades → remediada al 100% el mismo día.
- **5ª (2026-08-12)** — proyecto completo, 7 dimensiones + verificación
  adversarial ampliada a las MEDIA — 1 ALTA · 13 MEDIA · 43 BAJA · 1 retirado
  → **remediada al 100% el mismo día** (detalle en la sección "5ª auditoría —
  remediación" de `memory.md`). Patrón que dejó: los defectos ya no están en
  los mecanismos sino en **qué le dice el sistema al operador cuando algo
  falla a medias**.
- **6ª (2026-08-19)** — lo nuevo desde la 5ª, con la 8ª dimensión (**Textos de
  los caminos de falla**, que encontró los 2 ALTA en su estreno y queda fija)
  y verificación con clics reales — 2 ALTA (consolidados) · 12 MEDIA ·
  30 BAJA · 1 degradado → **remediada al 100% el mismo ciclo** (detalle en
  "6ª auditoría — remediación" de `memory.md`). Patrón que dejó: los defectos
  viven en las **costuras** — la pieza nueva y el panel que la hospeda, las
  versiones en la ventana de despliegue, el estado del pedido y sus textos.

- **7ª (2026-08-22)** — la funcionalidad de promociones (~1,900 líneas nuevas),
  8 dimensiones + verificación adversarial en tres frentes — **2 ALTA · 12
  MEDIA · 21 BAJA · 1 refutado · 2 no alcanzables** → **remediada al 100% el
  mismo ciclo** (detalle en "7ª auditoría — remediación" de `memory.md`). Los
  dos ALTA salieron de la misma raíz: el modal que carga su contenido después
  de abrirse rompió el apilamiento y el foco, y **ninguno era visible leyendo
  código** — hicieron falta clics reales y `elementFromPoint`. Patrón que dejó:
  los defectos migraron de las costuras (6ª) a las **capas**. Y por tercera
  auditoría seguida, lo que falló en las mediciones fue el **recorte**, no la
  consulta: tres cifras muy citadas estaban mal, dos de ellas ya escritas en
  `docs/` como dato firme.

El detalle de las dos primeras está en `docs/auditorias-2026-07.md`; el de la
3ª y la 4ª, en sus secciones de remediación de `memory.md`. Los reportes
completos se publicaron como artifacts (las URLs las tiene el usuario).
