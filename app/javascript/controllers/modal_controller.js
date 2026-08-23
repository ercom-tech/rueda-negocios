import { Controller } from "@hotwired/stimulus"

// Modal simple: muestra/oculta un target overlay. Cierra con backdrop, Esc o
// botón. Uso: data-controller="modal" en un contenedor, con un botón
// data-action="modal#open" y el overlay data-modal-target="dialog" (con
// style="display:none" inicial y role="dialog"/aria-modal).
//
// Un contenedor puede tener VARIOS diálogos: el botón elige el suyo con
// data-modal-dialog-param="<id>". Sin el param abre el primero, que es como
// se comportaban todos los usos anteriores. Existe para los modales de
// promoción: son uno por promoción y los abren botones repartidos por toda
// la tabla de partidas, así que un diálogo por fila serían decenas de copias
// idénticas repintándose en cada cambio de cantidad.
//
// Accesibilidad: al abrir, recuerda quién tenía el foco, lo mueve al primer
// control del diálogo y atrapa Tab dentro (focus-trap). Al cerrar, devuelve el
// foco a donde estaba.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event?.preventDefault()
    const requested = event?.params?.dialog
    const dialog = requested
      ? this.dialogTargets.find((d) => d.id === requested)
      : this.dialogTargets[0]
    if (!dialog) return

    this.previouslyFocused = document.activeElement
    this.openDialog = dialog
    dialog.style.display = "flex"
    this.refresh(dialog)
    this.trapHandler = (e) => this.trap(e)
    document.addEventListener("keydown", this.trapHandler)
    this.focusInside()
  }

  // Mete el foco al diálogo, y lo reintenta cuando llega el contenido.
  //
  // En un diálogo cuyo contenido viaja en un turbo-frame, al abrir solo está
  // el placeholder — que no tiene ningún elemento enfocable. El foco se
  // quedaba fuera para siempre (nadie reintentaba), y con él:
  //   - el `trap` no atrapaba nada, porque compara el elemento activo contra
  //     el primero y el último del diálogo. Tab se iba a los controles de la
  //     tabla, DETRÁS del overlay: tres tabuladores y una tecla cambiaban la
  //     cantidad de una partida a ciegas (7ª auditoría).
  //   - un lector de pantalla no anunciaba nada, y con `aria-modal="true"` el
  //     resto de la página queda oculto: no quedaba nada alcanzable.
  //
  // El contenedor lleva `tabindex="-1"` para poder recibir el foco cuando
  // todavía no hay ningún control dentro.
  focusInside() {
    const dialog = this.current
    if (!dialog) return

    const target = this.focusables()[0] || dialog
    target.focus()

    // El frame avisa cuando termina de cargar; entonces sí hay botones.
    dialog.addEventListener("turbo:frame-load", () => {
      if (this.isOpen) this.focusables()[0]?.focus()
    }, { once: true })
  }

  // El turbo-frame no pudo traer su contenido (la laptop-servidor ocupada, un
  // salto del wifi del salón). Turbo NO reintenta y no se recupera solo al
  // volver la red, así que sin esto el diálogo se quedaba diciendo "Cargando"
  // indefinidamente — y en tablet, sin tecla Esc, eso se lee como que la app
  // se trabó (7ª auditoría).
  loadFailed(event) {
    const placeholder = event.target.closest("[data-modal-target='dialog']")
      ?.querySelector("[data-modal-target='loading']")
    if (!placeholder) return

    placeholder.textContent =
      "No se pudo cargar la promoción. Ciérrala y vuelve a abrirla; " +
      "si sigue igual, avísale al equipo del servidor."
  }

  // Un diálogo `data-turbo-permanent` conserva su subárbol entero entre
  // repintados, así que su contenido se queda congelado en el estado que
  // tenía al pintarse. Los que marcan su turbo-frame con `data-modal-refresh`
  // lo vuelven a pedir al abrirse: es lo que mantiene al modal de promoción
  // hablando del pedido de AHORA (acumulado, escalón, aplicada o no) sin
  // perder el estado abierto cuando la tabla se repinta debajo.
  refresh(dialog) {
    dialog.querySelector("turbo-frame[data-modal-refresh]")?.reload()
  }

  close(event) {
    event?.preventDefault()
    if (!this.isOpen) return

    this.current.style.display = "none"
    this.openDialog = null
    document.removeEventListener("keydown", this.trapHandler)
    this.previouslyFocused?.focus()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.trapHandler)
  }

  // El diálogo abierto, o el primero como respaldo: el `closeOnEsc` global
  // puede llegar antes de que ninguno se haya abierto en esta conexión.
  get current() {
    return this.openDialog || this.dialogTargets[0]
  }

  get isOpen() {
    return this.current && this.current.style.display !== "none"
  }

  // Mantiene el foco dentro del diálogo mientras esté abierto.
  trap(event) {
    if (event.key !== "Tab") return

    const items = this.focusables()
    if (items.length === 0) return

    const first = items[0]
    const last = items[items.length - 1]
    // Si el foco se quedó FUERA, traerlo de vuelta. Comparar solo contra el
    // primero y el último dejaba pasar cualquier otro caso, y con el foco en
    // la página de atrás eso significaba tabular hasta los controles ocultos
    // por el overlay y editarlos a ciegas (7ª auditoría).
    if (!this.current.contains(document.activeElement)) {
      event.preventDefault()
      ;(event.shiftKey ? last : first).focus()
    } else if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  focusables() {
    return Array.from(
      this.current.querySelectorAll(
        'a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => !el.disabled && el.offsetParent !== null)
  }
}
