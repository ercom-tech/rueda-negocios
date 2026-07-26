import { Controller } from "@hotwired/stimulus"

// Aviso flash: se oculta solo tras unos segundos y también se puede cerrar a
// mano con el botón ✕. Uso: data-controller="flash" en el mensaje; el botón de
// cierre usa data-action="flash#dismiss". Ajusta el tiempo con
// data-flash-delay-value (ms; 0 desactiva el auto-cierre).
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    if (this.delayValue > 0) {
      this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    clearTimeout(this.timeout)
    this.element.remove()
  }
}
