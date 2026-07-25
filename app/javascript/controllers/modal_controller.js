import { Controller } from "@hotwired/stimulus"

// Modal simple: muestra/oculta un target overlay. Cierra con backdrop, Esc o
// botón. Uso: data-controller="modal" en un contenedor, con un botón
// data-action="modal#open" y el overlay data-modal-target="dialog" (con
// style="display:none" inicial).
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event?.preventDefault()
    this.dialogTarget.style.display = "flex"
  }

  close(event) {
    event?.preventDefault()
    this.dialogTarget.style.display = "none"
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
