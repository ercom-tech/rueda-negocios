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

### Excepciones registradas

Todas comparten justificación: **espejar el ERP hace evidente el mapeo**, y
traducirlas lo escondería.

1. **`orders.dividir_facturas`** (columna, atributo y parámetro): espeja
   literalmente `vta_pedido.dividir_facturas`.
2. **El rol `capturista`** (`users.role`): es el término con el que FECEGO
   nombra ese puesto, y aparece en pantalla. Genera `User.capturista` y
   `capturista?`.
3. **En `rueda-api`, lo que espeja al ERP**: `EMPRESA`, `prefijo`/`prefijo_for`,
   `clave`, `id_rueda`/`for_rueda`, los alias de las CTE (`marcas`, `provs`) y
   **las llaves del payload** (`clave_cliente`, `fecha_pedido`,
   `descto_porcentaje`…). Ese repo vive pegado al esquema del ERP: traducirlos
   dejaría el SQL mitad y mitad, que es peor que cualquiera de los dos idiomas
   completo. Cuidado especial con las llaves del payload — son el contrato de
   red con `Sync::Up#build_payload`, así que un renombre "por consistencia"
   rompe el sync-up y el síntoma es un 422 en pleno cierre de evento.

Cualquier excepción nueva se registra aquí con su porqué. Lo que **no** es
excepción: variables locales, métodos y constantes que no espejan nada del ERP
—van en inglés aunque el comentario de arriba esté en español, que es
justamente cuando se cuelan.

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

## Dónde vive cada cosa

- **Todo el HTTP hacia `rueda-api` pasa por `Sync::ApiClient`.** Es el punto
  único donde viven la URL, los timeouts y —cuando entren— los tokens y el TLS.
  Una clase que arme su propio `Net::HTTP` queda fuera del endurecimiento sin
  que nada lo delate hasta el 401.
- **Un porcentaje (o cualquier cifra) que ve el usuario se le pide al objeto
  que lo aplica, nunca a la regla de la que sale.** La vista leía
  `tier.discount_percent` y el flash tomaba el de la primera partida; con
  override por producto —FANAL: escalón 0%, códigos al 10% y 20%— la pantalla
  anunciaba "0% de descuento" sobre partidas al 10 y al 20, y el flash mentía
  en las dos direcciones según el orden de captura (7ª auditoría).
- **Una consulta con criterio de negocio va al modelo, no al controlador.**
  `Product.search` y `Client.search` son scopes porque su relevancia la reusan
  varias pantallas; como método privado de un controlador, el siguiente que la
  necesite la copia y el mismo concepto pasa a significar dos cosas.
- **Un `yield` solo funciona en un partial renderizado con `layout:`.** En un
  `render "x"` normal rinde vacío, sin error: el partial parece correcto y
  produce una pantalla en blanco.
- **Un panel absoluto no hace crecer la página, y el shell lo recorta.** El
  shell del sitio lleva `overflow-hidden` (contiene el patrón de
  herramientas), así que un dropdown abierto cerca del borde inferior se corta
  y no queda scroll con el que llegar a lo que falta — el combo de "Dividir
  facturas", último campo del paso 1, mostraba 3 de sus 6 montos. Cualquier
  capa flotante nueva que se despliegue hacia abajo tiene que medir el espacio
  y voltearse o acotarse (ver `select#position`), no confiar en que la página
  crezca. En pantalla baja aplica a casi todos los combos, no solo al último.
- **El rótulo visible de un combo custom no es un `<label>`:** el control es un
  `<button>`, así que la asociación va por `aria-label`. Sin él, todos los
  combos se anuncian igual y los mensajes que nombran un campo no se pueden
  emparejar con su control.

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
- **Un `z-index` sobre un wrapper crea contexto de apilamiento y encierra a los
  modales que contenga.** Es la otra mitad de la regla de los wrappers
  hermanos: si DOS regiones hermanas contienen modales, no basta con darle
  z-20 a una — la otra queda encerrada y su `z-50` deja de contar contra la
  página. La salida es que **ninguna de las dos lleve z-index**, y que los
  diálogos `fixed z-50` compitan en el contexto raíz. El síntoma es sutil: la
  barra superior se pinta sobre el modal y un toque cerca de su borde acciona
  un botón del header — en `orders/show` eso era "Cerrar sesión" a media
  captura (7ª auditoría).
- **En un diálogo que carga su contenido después de abrirse, el foco hay que
  reintentarlo.** `focusables()[0]` al abrir encuentra el placeholder, que no
  tiene ninguno, y el foco se queda fuera para siempre: el focus-trap no
  atrapa (compara contra el primero y el último del diálogo, y el activo no es
  ninguno) y Tab pasea por los controles de atrás, bajo el overlay, donde una
  tecla los edita a ciegas. Además, **un control de escape (Cerrar) tiene que
  vivir FUERA del frame**: si la carga falla, dentro no queda nada.
- **`data-turbo-permanent` conserva el subárbol ENTERO, así que congela el
  contenido.** Es la otra cara de lo anterior: protege el estado "abierto",
  pero un diálogo que también tiene que mostrar datos frescos no puede
  renderizarse de fábrica — se queda en el estado que tenía al pintarse la
  región. La salida es partirlo: cascarón permanente + contenido en un
  `turbo-frame` que se recarga al abrir (ver `orders/_promotion_modal` y
  `modal#refresh`). El síntoma sin esto es un modal que sigue ofreciendo la
  acción que ya se ejecutó.
- **Un modal que actúa debe cerrarse al terminar**
  (`turbo:submit-end->modal#close`). Si se queda abierto tapa justo lo que el
  usuario quiere revisar, y su fondo (`bg-black/50`) se come el siguiente
  clic: el segundo defecto no se ve, solo se siente como "el botón no sirve".
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

## PDF (Prawn)

- **Un `bounding_box` sin `height` hereda como alto lo que sobre de la hoja.**
  Si lo que va dentro no cabe en ese resto, prawn-table lo **pagina renglón por
  renglón** —una hoja por renglón— y, si el cursor quedó pegado al margen, no
  dibuja **nada**: el contenido no se escribe a ningún stream y `render`
  devuelve el documento sin levantar excepción ni log. Así salía el pie del
  pedido (importe en letra + los cuatro totales) en el 2% de los casos, con
  hojas en blanco detrás, en el papel que firma el cliente.
  Todo bloque que deba salir entero mide su alto y salta de hoja antes:
  `pdf.start_new_page if pdf.cursor < alto`. El alto de una tabla se obtiene
  con **`pdf.make_table(rows, …).height`** —construir sin dibujar— y el de un
  texto con `height_of` / `height_of_formatted`.
- **`pdf.group` NO existe como salida.** En prawn 2.5.0 está deshabilitado y
  levanta `NotImplementedError` ("lead to corrupted documents whenever a page
  boundary was crossed"). Es la primera sugerencia que aparece al buscar el
  problema anterior, y cuesta un ciclo entero comprobarla.
- **La franja mala no es un número de partidas, es una posición.** Se repite
  cerca de **cada** frontera de página y se mueve con el alto de la tabla: la
  dispara igual una descripción que se parte en dos líneas. Los regalos la
  vuelven mucho más probable (el prefijo "REGALO — " deja el 82% de los
  renglones a doble alto) y además **no cuentan contra `MAX_ITEMS`**, así que
  el impreso puede rebasar los 45 renglones. Por eso la prueba **barre un
  rango** en vez de fijar un conteo.
- **Extraer el texto del stream no prueba que se VEA.** Un bloque tapado por la
  tabla que se dibuja encima se extrae idéntico a uno visible; lo que hay que
  medir ahí es el espacio **reservado** frente al **ocupado**. Y al revés: para
  ver si algo se partió entre hojas hay que leer el texto **por página**,
  porque juntando las páginas un pie repartido en cuatro se lee como uno bien
  puesto.

## Jobs y estado de corridas

- Un registro de corrida (`SyncRun`) nace `running` con el **pid de su
  proceso dueño**, y solo su dueño la cierra (los rake con `ensure`, que sí
  corre ante Ctrl-C/kill). El barrido de huérfanos (`recover_orphaned!`) es
  seguro **por pid, no por contexto**: respeta corridas cuyo proceso vive
  (un rake en otra terminal, un worker aparte) y cierra las muertas —
  incluida la del pid reciclado tras un reinicio, porque una corrida
  iniciada antes del boot actual tiene al dueño muerto por definición. Por
  eso corre al bootear el server Y al cargar el menú del servidor: nada
  queda `running` para siempre. Una escritura nueva de corridas debe
  registrar a su dueño real (si un job pasara a un worker, actualizar
  `run.pid` en `perform`).
- Las condiciones previas se validan **antes de crear la corrida** —en el
  controlador y en el rake—: si se validan dentro del job, una condición que
  nunca llegó a intentarse queda registrada como corrida *fallida*. El job
  conserva la misma guarda como red para las carreras.
- **Mientras hay un `SyncRun` vivo, la captura se pausa**
  (`pause_writes_during_sync`). Solo las escrituras: leer, el reporte y el PDF
  siguen disponibles. Una acción nueva que escriba tiene que sumarse a esa
  lista, o reabre el hueco — el sync-down vacía el catálogo dentro de su
  transacción y un INSERT concurrente revienta con violación de llave foránea.
- **Todo dato nuevo del `summary` de un sync tiene que aterrizar en el panel
  del servidor Y en la tarea rake.** Calcularlo y guardarlo no es reportarlo:
  ya pasó en la 5ª (`skipped_users`) y volvió a pasar en la 7ª
  (`skipped_promotion_products`, `shared_promotion_products`). El panel es el
  camino del operador; el rake, el de consola.
- **Una validación `on: :update` NO cubre `destroy`.** Un candado de negocio
  que impide editar tiene que impedir borrar con un `before_destroy` que haga
  `throw :abort` — `destroy` no corre validaciones. Esconder el control en la
  vista no basta: el endpoint sigue vivo para una pestaña rezagada.
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
- **Una prueba que pasa puede estar pasando por el camino equivocado.** No es
  exclusivo de las pruebas de sistema: en un modelo con varias validaciones,
  la que rechaza el guardado puede no ser la que se quería probar (un
  `max_discount` bajo hacía que fallara `discount_within_limits` en vez del
  candado de promoción, y la prueba salía verde con y sin el arreglo). La
  comprobación que sirve es **romper a propósito el código que se está
  probando y ver que la prueba falle** — leer el código no la caza. Vale para
  toda prueba nueva, no solo para las de sistema.
- **Renombres masivos con expresiones regulares: revisar el diff palabra por
  palabra.** Un `\bcoincide\b` pensado para una variable también reescribe el
  texto visible ("Ningún pedido coincide") y los comentarios. Proteger las
  comillas **no basta**: el texto visible también vive dentro de literales de
  expresión regular (`assert_match(/Hay 1 pedido en borrador/, …)`), y ahí un
  `borrador → draft` pasa desapercibido hasta que falla la prueba. La
  comprobación que sí sirve es listar todo el texto en español que toca el diff
  —cadenas **y** regexes— y leerlo.
- **Validación en navegador:** levantar un servidor efímero en otro puerto y en
  `127.0.0.1` (no `localhost`: las cookies ignoran el puerto y se pisaría la
  sesión del usuario). Usar datos efímeros propios y borrarlos al terminar;
  nunca tocar los pedidos ni los usuarios del usuario.
- Al terminar, **matar el servidor efímero**: un proceso huérfano sigue
  sirviendo código viejo en silencio y el siguiente cambio "no funciona".
- Trampa de CDP: `element.focus()` **no** dispara el evento `focus` si la
  ventana no tiene el foco del sistema operativo — despachar `FocusEvent` a
  mano.
