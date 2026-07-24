import { Controller } from "@hotwired/stimulus"

// Envía el formulario contenedor cuando un control dispara la acción
// (p.ej. change en un <select>). Uso: data-controller="form-submit" en el
// <form> y data-action="change->form-submit#submit" en el control.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
