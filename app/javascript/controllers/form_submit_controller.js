import { Controller } from "@hotwired/stimulus"

// Envía el formulario contenedor cuando un control dispara la acción
// (p.ej. change en un <select>). Uso: data-controller="form-submit" en el
// <form> y data-action="change->form-submit#submit" en el control.
//
// Feedback opcional de auto-guardado: con un target "status" y
// data-action="turbo:submit-end->form-submit#flashStatus" en el form, muestra
// el aviso ("Guardado ✓") unos segundos tras cada envío exitoso.
export default class extends Controller {
  static targets = ["status"]

  submit() {
    this.element.requestSubmit()
  }

  flashStatus(event) {
    if (!this.hasStatusTarget || event.detail?.success === false) return

    this.statusTarget.classList.remove("opacity-0")
    clearTimeout(this._statusTimer)
    this._statusTimer = setTimeout(() => this.statusTarget.classList.add("opacity-0"), 2000)
  }

  disconnect() {
    clearTimeout(this._statusTimer)
  }
}
