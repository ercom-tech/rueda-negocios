# Convenciones de código

Normas y trampas ya pagadas en este proyecto. Se cargan en contexto desde
`CLAUDE.md`. El relato de cada hallazgo vive en `memory.md`.

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
- Las condiciones previas se validan **en el controlador, antes de crear la
  corrida**: si se validan dentro del job, una condición que nunca llegó a
  intentarse queda registrada como corrida *fallida*. El job conserva la misma
  guarda como red para las carreras.

## Validación

- Suite: `PARALLEL_WORKERS=1 bin/rails test`. El runner paralelo de minitest a
  veces se cuelga en `at_exit` después de terminar (sleep eterno).
- `bin/rails runner - <<'RUBY' … RUBY` (heredoc con comillas): pasar el script
  como argumento en una línea se come las comillas internas.
- **Validación en navegador:** levantar un servidor efímero en otro puerto y en
  `127.0.0.1` (no `localhost`: las cookies ignoran el puerto y se pisaría la
  sesión del usuario). Usar datos efímeros propios y borrarlos al terminar;
  nunca tocar los pedidos ni los usuarios del usuario.
- Al terminar, **matar el servidor efímero**: un proceso huérfano sigue
  sirviendo código viejo en silencio y el siguiente cambio "no funciona".
- Trampa de CDP: `element.focus()` **no** dispara el evento `focus` si la
  ventana no tiene el foco del sistema operativo — despachar `FocusEvent` a
  mano.
