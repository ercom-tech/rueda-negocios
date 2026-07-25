import { Controller } from "@hotwired/stimulus"

// Combo box custom (reemplaza <select> nativo). Un botón abre un panel de
// opciones estilizado; al elegir, actualiza un input hidden y dispara "change".
// Opcionalmente filtrable por texto. Navegación con ↑/↓/Enter, cierra con
// Esc o clic afuera.
// Uso: data-controller="select" con targets button/label/input/panel/list
//   (filter opcional) y data-action="click@window->select#hide".
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
    if (this.filterableValue && this.hasFilterTarget) {
      this.filterTarget.value = ""
      this.applyFilter("")
      this.filterTarget.focus()
    }
  }

  close() {
    this.panelTarget.hidden = true
    this.index = -1
  }

  choose(event) {
    const btn = event.currentTarget
    this.inputTarget.value = btn.dataset.value
    this.labelTarget.textContent = btn.dataset.label
    this.labelTarget.classList.toggle("opacity-60", btn.dataset.value === "")
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
      li.querySelector("button").style.backgroundColor = i === this.index ? "rgb(229 229 229)" : ""
    })
    items[this.index]?.scrollIntoView({ block: "nearest" })
  }

  hide(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  get optionItems() {
    return Array.from(this.listTarget.querySelectorAll("li"))
  }

  get visibleItems() {
    return this.optionItems.filter((li) => !li.hidden)
  }
}
