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
    // ARIA honesto mientras el formulario vive en el panel del combobox: un
    // listbox solo admite opciones (el lector anunciaba "cuadro de lista"
    // con un formulario adentro) y aria-expanded se quedaba en false.
    this._panel = this.element.closest("[role]")
    this._prevRole = this._panel?.getAttribute("role")
    this._panel?.setAttribute("role", "dialog")
    this._panel?.setAttribute("aria-label", "Producto fuera de catálogo")
    this._combo = document.querySelector('[aria-controls="product-search-results"]')
    this._combo?.setAttribute("aria-expanded", "true")
  }

  disconnect() {
    if (this._panel && this._prevRole) this._panel.setAttribute("role", this._prevRole)
    this._combo?.setAttribute("aria-expanded", "false")
  }
}
