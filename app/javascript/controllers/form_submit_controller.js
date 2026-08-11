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

  // Variante para inputs numéricos con flechitas (cantidad/descuento): cada
  // flecha dispara `change`, y enviar ahí reemplaza la tabla por Turbo y mata
  // el foco (el cursor "brincaba"). Se recuerda el valor al ENTRAR al campo y
  // se envía SOLO al salir, si cambió. Uso:
  //   data-action="focus->form-submit#remember blur->form-submit#submitIfChanged"
  remember(event) {
    event.target.dataset.initialValue = event.target.value
  }

  submitIfChanged(event) {
    if (event.target.value === event.target.dataset.initialValue) return

    this.element.requestSubmit()
  }

  // Flechas ↑/↓ en esos mismos inputs: con step="any" (necesario para
  // decimales) Chrome NO aplica la flecha al valor y la tecla cae al scroll
  // de la página ("se sube a la primera fila"). Se implementa el paso de ±1
  // a mano, acotado a min/max, y se consume la tecla.
  stepWithArrows(event) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return

    event.preventDefault()
    const input = event.target
    const dir = event.key === "ArrowUp" ? 1 : -1
    const step = parseFloat(input.dataset.stepSize)
    const current = parseFloat(input.value) || 0
    let next
    if (step) {
      // Producto con empaque: la flecha va al SIGUIENTE múltiplo en su
      // dirección (10→20→30; un 15 tecleado va a 20 con ↑ y a 10 con ↓),
      // sin bajar del empaque (10↓ se queda en 10, no cae a 1).
      next = dir > 0 ? Math.floor(current / step) * step + step
                     : Math.ceil(current / step) * step - step
      if (next < step) next = step
    } else {
      next = current + dir
    }
    const min = parseFloat(input.min)
    const max = parseFloat(input.max)
    if (!Number.isNaN(min)) next = Math.max(min, next)
    if (!Number.isNaN(max)) next = Math.min(max, next)
    input.value = next
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
