import { Controller } from "@hotwired/stimulus"

// Combo box custom (reemplaza <select> nativo). Un botón abre un panel de
// opciones estilizado; al elegir, actualiza un input hidden y dispara "change".
// Opcionalmente filtrable por texto. Navegación con ↑/↓/Enter, cierra con
// Esc o clic afuera.
// Uso: data-controller="select" con targets button/label/input/panel/list
//   (filter opcional) y data-action="click@window->select#hide".
//
// Accesibilidad: el botón es aria-haspopup="listbox" y refleja aria-expanded;
// la lista es role="listbox" con options role="option"/aria-selected. El
// resaltado del teclado se expone con aria-activedescendant en el elemento con
// foco (el botón, o el campo de filtro cuando es filtrable).
export default class extends Controller {
  static targets = ["button", "label", "input", "panel", "filter", "list"]
  static values = { filterable: Boolean }

  connect() {
    this.index = -1
  }

  toggle(event) {
    event.preventDefault()
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.index = -1
    this.buttonTarget.setAttribute("aria-expanded", "true")
    if (this.filterableValue && this.hasFilterTarget) {
      this.filterTarget.value = ""
      this.applyFilter("")
      this.filterTarget.focus()
    }
  }

  close() {
    this.panelTarget.hidden = true
    this.index = -1
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.focusHost.removeAttribute("aria-activedescendant")
  }

  choose(event) {
    const btn = event.currentTarget
    this.inputTarget.value = btn.dataset.value
    this.labelTarget.textContent = btn.dataset.label
    this.labelTarget.classList.toggle("opacity-60", btn.dataset.value === "")
    this.optionItems.forEach((li) => {
      const opt = li.querySelector("button")
      opt.setAttribute("aria-selected", opt === btn ? "true" : "false")
    })
    this.close()
    this.buttonTarget.focus()
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  filter(event) {
    this.applyFilter(event.target.value)
  }

  applyFilter(q) {
    const needle = q.trim().toLowerCase()
    this.optionItems.forEach((li) => {
      li.hidden = needle !== "" && !li.textContent.trim().toLowerCase().includes(needle)
    })
    this.index = -1
  }

  navigate(event) {
    // Con el panel cerrado, las flechas lo abren (foco en el botón).
    if (this.panelTarget.hidden) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        this.open()
      }
      return
    }

    const items = this.visibleItems
    if (items.length === 0) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.index = Math.min(this.index + 1, items.length - 1)
        this.highlight(items)
        break
      case "ArrowUp":
        event.preventDefault()
        this.index = Math.max(this.index - 1, 0)
        this.highlight(items)
        break
      case "Enter":
        event.preventDefault()
        if (this.index >= 0) items[this.index].querySelector("button").click()
        break
      case "Escape":
        this.close()
        this.buttonTarget.focus()
        break
    }
  }

  highlight(items) {
    items.forEach((li, i) => {
      li.querySelector("button").style.backgroundColor = i === this.index ? "rgba(0, 0, 0, 0.08)" : ""
    })
    const current = items[this.index]?.querySelector("button")
    if (current) this.focusHost.setAttribute("aria-activedescendant", current.id)
    items[this.index]?.scrollIntoView({ block: "nearest" })
  }

  hide(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  // Elemento con foco mientras el panel está abierto: el campo de filtro si es
  // filtrable, el botón en caso contrario.
  get focusHost() {
    return this.filterableValue && this.hasFilterTarget ? this.filterTarget : this.buttonTarget
  }

  get optionItems() {
    return Array.from(this.listTarget.querySelectorAll("li"))
  }

  get visibleItems() {
    return this.optionItems.filter((li) => !li.hidden)
  }
}
