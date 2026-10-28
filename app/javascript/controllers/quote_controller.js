import { Controller } from "@hotwired/stimulus"

// Cotizador de la captura (2026-10-09). Recuerda la partida seleccionada y, al
// picar "Cotizador", abre el modal con ella. Hace falta recordarla: al picar
// el botón el foco ya salió de la fila.
//
// SIEMPRE hay una seleccionada mientras el pedido tenga partidas (14ª
// auditoría): al abrir, la más reciente (la primera de la tabla); al agregar
// un producto, su fila nueva — el alta no le da el foco, y sin esto se
// cotizaba la partida de antes; y la que se toque o se enfoque. Con el botón
// deshabilitado hasta tocar una fila, en tablet no había forma de saber por
// qué no respondía (el `title` no existe en pantalla táctil).
//
// La tabla y el buscador se repintan con morph en cada alta, baja y cambio de
// cantidad, e idiomorph regresa los atributos al HTML del servidor —que no
// sabe cuál fila está seleccionada—: el realce de la fila y el nombre del
// botón se borraban. Por eso se vuelven a aplicar DESPUÉS de cada stream
// (`turbo:before-stream-render` envolviendo su `render`). La selección vive
// en el id de la fila (`dom_id`), que el morph conserva.
//
// Los regalos no llevan `data-quote-url`: no se cotizan (los pone la
// promoción, a 100% de descuento).
export default class extends Controller {
  static targets = ["button"]
  static outlets = ["modal"]

  connect() {
    // Las filas que ya estaban no son "recién agregadas"; sin selección,
    // `sync` toma la más reciente.
    this.knownIds = new Set(this.rows.map((tr) => tr.id))
    this.selectedId = null
    this.wrapStreamRender = (event) => {
      const render = event.detail.render
      event.detail.render = async (stream) => {
        await render(stream)
        this.sync()
      }
    }
    document.addEventListener("turbo:before-stream-render", this.wrapStreamRender)
    this.sync()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.wrapStreamRender)
  }

  select(event) {
    const row = event.target.closest?.("tr[data-quote-url]")
    if (!row || !this.element.contains(row)) return

    this.selectedId = row.id
    this.sync()
  }

  open() {
    if (!this.hasModalOutlet) return

    const frame = this.modalOutlet.element.querySelector("turbo-frame")
    const row = this.selectedRow
    if (!row) {
      // Pedido sin partidas cotizables (vacío, o solo regalos).
      this.fill(frame, "empty")
      this.modalOutlet.open()
      return
    }

    // El contenido de la partida anterior no debe verse mientras carga la
    // nueva: se pone el "Cargando" de la plantilla del servidor.
    this.fill(frame, "loading")
    // Absoluta: Turbo guarda el `src` resuelto, y la fila trae una ruta
    // relativa. Comparando tal cual nunca coincidían y esta rama era código
    // muerto — funcionaba de rebote, porque reasignar el mismo destino con
    // otra escritura sí recarga (15ª auditoría).
    const url = new URL(row.dataset.quoteUrl, document.baseURI).href
    // Turbo no vuelve a pedir un `src` que no cambió: misma partida, reload.
    if (frame.getAttribute("src") === url) frame.reload()
    else frame.src = url
    this.modalOutlet.open()
  }

  // Selección, realce y nombre del botón. Una fila que no se conocía es una
  // partida recién agregada: gana la selección. Si la seleccionada se quitó,
  // la toma la más reciente.
  sync() {
    const rows = this.rows
    const added = rows.find((tr) => !this.knownIds.has(tr.id))
    this.knownIds = new Set(rows.map((tr) => tr.id))
    if (added) this.selectedId = added.id
    if (!this.selectedRow) this.selectedId = rows[0]?.id ?? null
    const row = this.selectedRow

    rows.forEach((tr) => {
      const selected = tr === row
      // Se distingue por FORMA, no solo por color (14ª auditoría): el tinte
      // dorado sobre el crema da 1.16:1 —un matiz, como el de la fila
      // bloqueada—, así que la fila lleva además una barra negra a la
      // izquierda (18:1). Dorado de superficie y no de trazo: un filete
      // dorado sobre el crema da 1.39:1.
      tr.style.backgroundColor = selected
        ? "color-mix(in srgb, var(--color-brand-gold) 45%, transparent)"
        : ""
      if (tr.cells[0]) tr.cells[0].style.boxShadow = selected ? "inset 4px 0 0 #000" : ""
      if (selected) tr.setAttribute("aria-current", "true")
      else tr.removeAttribute("aria-current")
    })

    if (!this.hasButtonTarget) return
    const label = row ? `Cotizar ${row.dataset.quoteLabel}` : "Cotizador"
    this.buttonTarget.title = label
    this.buttonTarget.setAttribute("aria-label", label)
  }

  get rows() {
    return Array.from(this.element.querySelectorAll("tr[data-quote-url]"))
  }

  get selectedRow() {
    if (!this.selectedId) return null
    const row = document.getElementById(this.selectedId)
    return row && this.element.contains(row) && row.dataset.quoteUrl ? row : null
  }

  // Reemplaza el contenido del frame con una de las plantillas del cascarón
  // (`_quote_modal`): "loading" o "empty".
  fill(frame, name) {
    const template = this.modalOutlet.element.querySelector(`template[data-quote-template="${name}"]`)
    frame.replaceChildren(template.content.cloneNode(true))
  }
}
