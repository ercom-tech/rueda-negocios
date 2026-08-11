import { Controller } from "@hotwired/stimulus"

// Elegir un producto del autocompletado del filtro del reporte: escribe su
// CÓDIGO en el campo y filtra. El código va a 6 dígitos, así que como texto de
// búsqueda identifica a ese producto y a ningún otro — y el campo sigue
// aceptando texto libre ("disco flap") para acotar a una familia entera.
//
// Uso: data-controller="autocomplete product-filter" en el contenedor, con
// data-product-filter-target="input" en el campo y, en cada sugerencia,
// data-action="click->product-filter#choose" + data-code.
export default class extends Controller {
  static targets = ["input"]

  choose(event) {
    event.preventDefault()
    this.inputTarget.value = event.currentTarget.dataset.code
    this.element.closest("form")?.requestSubmit()
  }
}
