import { Controller } from "@hotwired/stimulus"

// Mini-formulario del producto fuera de catálogo. Foco explícito al primer
// campo en connect(), como manda la convención: el atributo autofocus del
// contenido streameado perdía SIEMPRE contra el reenfoque del buscador tras
// el submit de "Capturar" (confirmado con clics reales, 6ª auditoría) — el
// capturista tecleaba la descripción en el buscador y destruía el formulario
// al primer carácter.
export default class extends Controller {
  connect() {
    this.element.querySelector("input[type='text']")?.focus()
  }
}
