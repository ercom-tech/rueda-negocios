import { Controller } from "@hotwired/stimulus"

// Autocompletado del buscador de cliente. Con debounce, pide sugerencias a
// /orders/client_options y las inyecta en el contenedor de resultados.
// Navegación por teclado: ↑/↓ mueve el resaltado, Enter selecciona, Esc cierra.
// Uso: data-controller="autocomplete" con
//   data-autocomplete-target="input"   en el <input>
//   data-autocomplete-target="results" en el contenedor del dropdown
//   data-autocomplete-url-value="/orders/client_options"
//   data-action="input->autocomplete#search keydown->autocomplete#navigate"
//
// Accesibilidad: el input es role="combobox" con aria-expanded/aria-activedescendant;
// mientras busca muestra "Buscando…" (role=status) y ante un fallo de red muestra
// un aviso de error (role=alert), en vez de fallar en silencio.
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
    this.showStatus("Buscando…", "status", "text-neutral-500")
    try {
      // La URL base puede ya traer query (p.ej. order_id al editar); se agrega q
      // con URLSearchParams para no romperla con un segundo "?".
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("q", q)
      const res = await fetch(url, { headers: { Accept: "text/html" } })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)

      this.resultsTarget.innerHTML = await res.text()
      this.index = -1
      this.tagOptions()
      this.setExpanded(this.items.length > 0)
    } catch (e) {
      this.showStatus("No se pudo buscar. Revisa la conexión e inténtalo de nuevo.", "alert", "text-red-600")
    }
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
      el.style.backgroundColor = i === this.index ? "rgba(0, 0, 0, 0.08)" : ""
    })
    const current = this.items[this.index]
    if (current) this.inputTarget.setAttribute("aria-activedescendant", current.id)
    else this.inputTarget.removeAttribute("aria-activedescendant")
    current?.scrollIntoView({ block: "nearest" })
  }

  get items() {
    return Array.from(this.resultsTarget.querySelectorAll("a, button"))
  }

  // Marca cada resultado como option del combobox y le asigna un id estable
  // para poder referirlo desde aria-activedescendant.
  tagOptions() {
    this.items.forEach((el, i) => {
      el.setAttribute("role", "option")
      el.id ||= `${this.resultsTarget.id || "ac"}-opt-${i}`
    })
  }

  showStatus(text, role, colorClass) {
    this.resultsTarget.innerHTML =
      `<div role="${role}" class="rounded-2xl border border-black/10 bg-brand-cream px-5 py-3 text-sm ${colorClass} shadow-xl">${text}</div>`
    this.index = -1
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.setExpanded(true)
  }

  setExpanded(open) {
    this.inputTarget.setAttribute("aria-expanded", open ? "true" : "false")
  }

  clear() {
    this.resultsTarget.innerHTML = ""
    this.index = -1
    this.setExpanded(false)
    this.inputTarget.removeAttribute("aria-activedescendant")
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
