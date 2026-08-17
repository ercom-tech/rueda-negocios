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
  // El valor recordado vive en el controller (Map por id), NO solo en el
  // data-attribute: un morph que repinta la fila ~60 ms después del blur
  // reescribe los atributos con el HTML del servidor y se lo quitaba al
  // campo enfocado — el revert de la pausa no revertía y submitIfChanged
  // reenviaba sin cambio (6ª auditoría). El atributo se conserva como
  // respaldo visible/depurable.
  remember(event) {
    ;(this._initial ||= new Map()).set(event.target.id || event.target.name, event.target.value)
    event.target.dataset.initialValue = event.target.value
  }

  rememberedValue(field) {
    const stored = this._initial?.get(field.id || field.name)
    return stored !== undefined ? stored : field.dataset.initialValue
  }

  submitIfChanged(event) {
    if (event.target.value === this.rememberedValue(event.target)) return

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
      //
      // La aritmética va en unidades ENTERAS del empaque: con pasos
      // decimales, la división flotante (0.3/0.1 = 2.9999…) atoraba la
      // flecha o dejaba 0.30000000000000004 visible en el campo.
      const decimals = (String(step).split(".")[1] || "").length
      const units = Math.round((current / step) * 1e6) / 1e6
      next = (dir > 0 ? Math.floor(units) + 1 : Math.ceil(units) - 1) * step
      next = parseFloat(next.toFixed(decimals))
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

  // Cierre de cada envío. Si falló (p. ej. la pausa durante un sync responde
  // 422): sin palomita, y los campos con valor recordado se revierten al
  // guardado — dejarlos con lo tecleado era doble mentira: la tabla no se
  // repinta (solo cambió el flash) y el siguiente blur ya no reenviaba
  // porque el valor "no cambió" respecto a lo tecleado. Si salió bien,
  // muestra el "Guardado ✓" unos segundos (cuando el form trae target).
  flashStatus(event) {
    if (event.detail?.success === false) {
      this.revertRemembered()
      return
    }
    if (!this.hasStatusTarget) return

    this.statusTarget.classList.remove("opacity-0")
    clearTimeout(this._statusTimer)
    this._statusTimer = setTimeout(() => this.statusTarget.classList.add("opacity-0"), 2000)
  }

  revertRemembered() {
    this.element.querySelectorAll("input, textarea").forEach((field) => {
      const initial = this.rememberedValue(field)
      if (initial !== undefined) field.value = initial
    })
  }

  disconnect() {
    clearTimeout(this._statusTimer)
  }
}
