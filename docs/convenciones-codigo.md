# Convenciones de código

Normas y trampas ya pagadas en este proyecto. Se cargan en contexto desde
`CLAUDE.md`. El relato de cada hallazgo vive en `memory.md`.

## Idioma: el código va en inglés

**Identificadores en inglés** — variables, métodos, constantes, clases,
columnas, locals de partials, targets y values de Stimulus. **Español solo en
los comentarios y en el texto que ve el usuario.**

Es fácil de romper justo porque los comentarios van en español: al terminar de
escribir uno, la variable siguiente sale en español sin pensarlo. Si el
comentario dice "el empaque mínimo", la variable sigue siendo `package_size`.

Excepción registrada: **`orders.dividir_facturas`** (columna, atributo y
parámetro) está en español a propósito, para espejar literalmente
`vta_pedido.dividir_facturas` del ERP y que el mapeo del sync sea evidente. Es
la única; cualquier otra hay que justificarla igual de explícito.

## Textos: `pluralize` es el inflector inglés

`pluralize(n, "palabra")` y `String#pluralize` aplican reglas del **inglés**.
Con la mayoría del vocabulario del proyecto acierta por casualidad (*pedido →
pedidos*, *cliente → clientes*), pero **no con todo**: `"capturista".pluralize`
devuelve `"capturista"`, y el texto sale con "2 capturista" sin que nada avise.

Antes de usarlo con una palabra nueva, comprobarla
(`bin/rails runner 'puts "palabra".pluralize'`). Si falla —o si la frase
necesita concordar además en verbo o artículo— escribir la concordancia a mano,
como hace `Sync::Guards`. La regla de concordancia siempre está en
`docs/convenciones-visuales.md`; esto es la trampa de la herramienta.

## Hotwire / Turbo

- **Nunca `link_to` con `data: { turbo_method: … }`.** Turbo intercepta el clic
  pero el form efímero no se somete: el POST jamás sale y no hay error en
  consola. Para toda acción no-GET, **`button_to`**.
- **Cuando el foco importa, `turbo_stream.replace(..., method: :morph)`.** Un
  replace normal destruye el nodo en el que el usuario está parado y el foco
  cae al `body` (en una tabla, la siguiente flecha scrollea al inicio).
  Idiomorph actualiza en sitio, **pero solo empareja nodos por id único**: hay
  que dar ids por fila a `tr`, forms e inputs (`dom_id(item, :quantity)`) —
  `form_with model:` repite el mismo id en todas las filas.
- **Morph también evita reconectar controllers Stimulus.** Si un partial se
  repinta seguido y su controller hace algo en `connect()` (enfocar, animar),
  con `replace` eso se dispara en cada repintado; con morph, no.
- **El atributo HTML `autofocus` no es confiable tras una visita Turbo.**
  Darlo explícito en el `connect()` del controller Stimulus, con un value para
  activarlo por pantalla.
- **Un diálogo dentro de una región que se repinta con morph necesita
  `data-turbo-permanent` y un id estable.** El estado "abierto" vive en un
  `style` en línea, y morph reescribe los atributos con los del HTML nuevo: el
  modal recién abierto se cierra solo. Pasaba al corregir una cantidad y tocar
  el bote de basura de otra fila —el `blur` dispara el repintado—, que es la
  pareja de acciones más común de la captura. El id tiene que venir del
  registro (`dom_id(item, :remove_dialog)`), nunca de un aleatorio: Turbo
  empareja por id para saber qué conservar.
- **No reconstruyas DOM que está recibiendo eventos de puntero.** Stimulus
  enlaza las acciones de los nodos nuevos de forma asíncrona
  (MutationObserver): si un `mousedown`/`mouseenter` regenera los elementos, el
  clic siguiente cae en un nodo todavía sin acción y se pierde. Construir la
  estructura una vez (al abrir, al cambiar de página/mes) y en la interacción
  **solo actualizar clases**. Falla intermitente e **invisible con eventos
  sintéticos**: hay que probar con clics reales.

## Formularios

- **Inputs numéricos con `step="any"`: Chrome no aplica las flechas ↑/↓** — la
  tecla cae al scroll de la página. Hay que implementar el paso a mano
  (`keydown` + `preventDefault`, acotado a `min`/`max`).
- **Enviar en `blur` solo si cambió**, no en `change`: con `change`, cada
  flecha dispara un submit que repinta la tabla y mata el foco.
- **Campo numérico vaciado llega como `""`.** Si la columna es NOT NULL, hay
  que normalizarlo (a 0) **antes** de validar: la validación deja pasar el
  blank y truena en la BD con `PG::NotNullViolation`.
- Cuando un campo tiene una regla de negocio con rejilla (múltiplos de un
  empaque), el `min` del input **es** el tamaño de la rejilla, y la flecha
  avanza al siguiente múltiplo en su dirección — si no, bajar desde el mínimo
  desalinea toda la secuencia.
- **Lo que el combo ofrece, el modelo lo valida.** Los selects del encabezado
  viajan en campos ocultos, así que la lista de opciones no es una restricción:
  hay que comprobar en el modelo que el valor esté en el catálogo y que los
  perfiles sean **del cliente del pedido**.
- **Todo campo numérico necesita tope superior, no solo inferior.** Rebasar la
  precisión de la columna sale como `ActiveRecord::RangeError`, que ningún
  rescue atrapa; y en una respuesta Turbo Stream el usuario ni siquiera ve el
  error: la pantalla no se repinta y parece que "no pasó nada".
- **Un enum no se puede validar en el modelo:** asignarle un valor desconocido
  levanta `ArgumentError` antes de que corra ninguna validación. Se sanea en
  los `params` (a nil) y se deja que lo recoja el `validates presence`.

## Consultas al ERP

- **Agregados: CTE con `GROUP BY`, nunca subquery correlacionada.** Una
  subquery por producto sobre `com_proveedor_has_producto` (13k ejecuciones)
  llevó el export a ~28s; con CTE + hash join bajó a **0.3s**.
- Códigos de producto: el ERP los muestra siempre a **6 dígitos**; comparar con
  `LPAD(...)` y no quitando ceros a la izquierda (quitarlos da coincidencias
  falsas: buscar `000081` traía `003381`, `008681`…).
- Las tablas de personas usan **0 como "sin valor"** (`id_proveedor`,
  `id_marca`): `NULLIF` al exportar, o se pierden filas legítimas.

## Jobs y estado de corridas

- Un registro de corrida (`SyncRun`) nace `running` y **solo el job lo cierra**:
  si el proceso muere a media corrida, queda `running` para siempre y bloquea
  las siguientes. El barrido de huérfanos va en
  `Rails.application.server { }` — ese hook corre **solo al bootear el
  servidor web**, no en consola, rake ni tests, donde un `running` puede ser
  legítimo porque el server sigue vivo.
- Las condiciones previas se validan **antes de crear la corrida** —en el
  controlador y en el rake—: si se validan dentro del job, una condición que
  nunca llegó a intentarse queda registrada como corrida *fallida*. El job
  conserva la misma guarda como red para las carreras.
- **Toda ruta que sincroniza abre su `SyncRun`, incluidas las tareas rake.** El
  lock y las guardas del panel se apoyan en `SyncRun.running.exists?`: una
  corrida que no se registra es invisible, y entonces "Cerrar rueda" se
  habilita encima de ella.
- **Una guarda antes de un borrado no cierra la carrera por sí sola:** son dos
  sentencias distintas y entre ellas otra conexión puede escribir. Acotar el
  borrado a lo que la guarda autorizó (`Order.transmitted`, no `Order`) y
  **volver a comprobar después**, dentro de la misma transacción, sí la cierra:
  si algo se coló, todo se deshace. Vale más que mover la guarda adentro del
  lock, que solo estrecha la ventana.

## Validación

- Suite: `PARALLEL_WORKERS=1 bin/rails test`. El runner paralelo de minitest a
  veces se cuelga en `at_exit` después de terminar (sleep eterno).
- **`bin/rails test` NO incluye las de sistema**: van aparte con
  `bin/rails test:system` (Chrome headless; Selenium Manager resuelve el driver
  solo). Son las únicas que ven los defectos que nacen entre Turbo, idiomorph y
  Stimulus. **Una prueba de sistema nueva se corre primero contra el código sin
  arreglar**: si no falla, no está probando el defecto — y con el DOM de por
  medio es fácil que pase por el camino equivocado.
- `bin/rails runner - <<'RUBY' … RUBY` (heredoc con comillas): pasar el script
  como argumento en una línea se come las comillas internas.
- **`node --check archivo.js` tras tocar un controller Stimulus.** El proyecto
  no necesita Node en runtime (importmap), pero está instalado y es lo único
  que caza un error de sintaxis antes del navegador — una continuación de línea
  estilo Ruby (`\`) en JS rompe el controller entero sin que nada más avise.
- **Renombres masivos con expresiones regulares: revisar el diff palabra por
  palabra.** Un `\bcoincide\b` pensado para una variable también reescribe el
  texto visible ("Ningún pedido coincide") y los comentarios.
- **Validación en navegador:** levantar un servidor efímero en otro puerto y en
  `127.0.0.1` (no `localhost`: las cookies ignoran el puerto y se pisaría la
  sesión del usuario). Usar datos efímeros propios y borrarlos al terminar;
  nunca tocar los pedidos ni los usuarios del usuario.
- Al terminar, **matar el servidor efímero**: un proceso huérfano sigue
  sirviendo código viejo en silencio y el siguiente cambio "no funciona".
- Trampa de CDP: `element.focus()` **no** dispara el evento `focus` si la
  ventana no tiene el foco del sistema operativo — despachar `FocusEvent` a
  mano.
