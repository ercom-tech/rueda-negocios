import { Controller } from "@hotwired/stimulus"

// Autocompletado del buscador de cliente. Con debounce, pide sugerencias a
// /orders/client_options y las inyecta en el contenedor de resultados.
// Navegación por teclado: ↑/↓ mueve el resaltado, Enter selecciona, Esc cierra.
// Uso: data-controller="autocomplete" con
//   data-autocomplete-target="input"   en el <input>
//   data-autocomplete-target="results" en el contenedor del dropdown
//   data-autocomplete-url-value="/orders/client_options"
//   data-action="input->autocomplete#search keydown->autocomplete#navigate"
export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String }

  connect() {
    this.index = -1
  }

  search() {
    clearTimeout(this._timer)
    const q = this.inputTarget.value.trim()
    if (q.length < 2) {
      this.clear()
      return
    }
    this._timer = setTimeout(() => this.fetch(q), 250)
  }

  async fetch(q) {
    // La URL base puede ya traer query (p.ej. order_id al editar); se agrega q
    // con URLSearchParams para no romperla con un segundo "?".
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)
    const res = await fetch(url, { headers: { Accept: "text/html" } })
    this.resultsTarget.innerHTML = await res.text()
    this.index = -1
  }

  navigate(event) {
    const items = this.items
    if (items.length === 0) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.index = Math.min(this.index + 1, items.length - 1)
        this.highlight()
        break
      case "ArrowUp":
        event.preventDefault()
        this.index = Math.max(this.index - 1, 0)
        this.highlight()
        break
      case "Enter":
        if (this.index >= 0 && items[this.index]) {
          event.preventDefault()
          items[this.index].click()
        }
        break
      case "Escape":
        this.clear()
        break
    }
  }

  highlight() {
    // Estilo inline (no clase Tailwind) porque se aplica dinámicamente y el
    // JIT no lo generaría al no aparecer en ninguna plantilla.
    this.items.forEach((el, i) => {
      el.style.backgroundColor = i === this.index ? "rgb(229 229 229)" : ""
    })
    this.items[this.index]?.scrollIntoView({ block: "nearest" })
  }

  get items() {
    return Array.from(this.resultsTarget.querySelectorAll("a, button"))
  }

  clear() {
    this.resultsTarget.innerHTML = ""
    this.index = -1
  }

  // Tras agregar (submit del resultado), limpia el input y los resultados y
  // reenfoca para encadenar una nueva búsqueda.
  reset() {
    this.inputTarget.value = ""
    this.clear()
    this.inputTarget.focus()
  }

  // Cierra el dropdown al hacer click fuera.
  hide(event) {
    if (!this.element.contains(event.target)) this.clear()
  }
}
