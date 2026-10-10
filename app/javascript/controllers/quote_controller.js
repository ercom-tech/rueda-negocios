import { Controller } from "@hotwired/stimulus"

// Cotizador de la captura (2026-10-09). Recuerda la última partida en la que
// estuvo el capturista —con el foco o con un toque— y, al picar "Cotizador",
// abre el modal con esa partida. Hace falta recordarla: al picar el botón el
// foco ya salió de la fila.
//
// La tabla y el buscador se repintan con morph en cada alta, baja y cambio de
// cantidad, e idiomorph regresa los atributos al HTML del servidor —que no
// sabe cuál fila está seleccionada—: el realce de la fila y el estado del
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
    const row = this.selectedRow
    if (!row || !this.hasModalOutlet) return

    const frame = this.modalOutlet.element.querySelector("turbo-frame")
    // El contenido de la partida anterior no debe verse mientras carga la
    // nueva: se regresa al "Cargando" de fábrica.
    this.placeholder ??= frame.innerHTML
    frame.innerHTML = this.placeholder
    const url = row.dataset.quoteUrl
    // Turbo no vuelve a pedir un `src` que no cambió: misma partida, reload.
    if (frame.getAttribute("src") === url) frame.reload()
    else frame.src = url
    this.modalOutlet.open()
  }

  // Realce de la fila y estado del botón, a partir de `selectedId`. Si la
  // partida seleccionada se quitó del pedido, la selección se suelta.
  sync() {
    let row = this.selectedRow
    if (!row) this.selectedId = null

    this.element.querySelectorAll("tr[data-quote-url]").forEach((tr) => {
      // Dorado de SUPERFICIE (tinte de fondo), no de trazo: un filete dorado
      // sobre el crema da 1.39:1 y no se ve (convenciones-visuales).
      tr.style.backgroundColor = tr === row
        ? "color-mix(in srgb, var(--color-brand-gold) 45%, transparent)"
        : ""
    })

    if (!this.hasButtonTarget) return
    const button = this.buttonTarget
    const enabled = Boolean(row)
    button.disabled = !enabled
    button.setAttribute("aria-disabled", String(!enabled))
    button.classList.toggle("opacity-60", !enabled)
    button.classList.toggle("cursor-not-allowed", !enabled)
    button.classList.toggle("cursor-pointer", enabled)
    button.classList.toggle("hover:bg-neutral-800", enabled)
    button.title = enabled
      ? `Cotizar ${row.dataset.quoteLabel}`
      : "Toca una partida de la tabla para cotizarla."
  }

  get selectedRow() {
    if (!this.selectedId) return null
    const row = document.getElementById(this.selectedId)
    return row && this.element.contains(row) && row.dataset.quoteUrl ? row : null
  }
}
