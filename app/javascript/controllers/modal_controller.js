import { Controller } from "@hotwired/stimulus"

// Modal simple: muestra/oculta un target overlay. Cierra con backdrop, Esc o
// botón. Uso: data-controller="modal" en un contenedor, con un botón
// data-action="modal#open" y el overlay data-modal-target="dialog" (con
// style="display:none" inicial y role="dialog"/aria-modal).
//
// Accesibilidad: al abrir, recuerda quién tenía el foco, lo mueve al primer
// control del diálogo y atrapa Tab dentro (focus-trap). Al cerrar, devuelve el
// foco a donde estaba.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event?.preventDefault()
    this.previouslyFocused = document.activeElement
    this.dialogTarget.style.display = "flex"
    this.trapHandler = (e) => this.trap(e)
    document.addEventListener("keydown", this.trapHandler)
    this.focusables()[0]?.focus()
  }

  close(event) {
    event?.preventDefault()
    if (!this.isOpen) return

    this.dialogTarget.style.display = "none"
    document.removeEventListener("keydown", this.trapHandler)
    this.previouslyFocused?.focus()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }

  disconnect() {
    document.removeEventListener("keydown", this.trapHandler)
  }

  get isOpen() {
    return this.dialogTarget.style.display !== "none"
  }

  // Mantiene el foco dentro del diálogo mientras esté abierto.
  trap(event) {
    if (event.key !== "Tab") return

    const items = this.focusables()
    if (items.length === 0) return

    const first = items[0]
    const last = items[items.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  focusables() {
    return Array.from(
      this.dialogTarget.querySelectorAll(
        'a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => !el.disabled && el.offsetParent !== null)
  }
}
