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
// A partir de cuántas opciones vale la pena enfocar el campo de filtro (ver
// `open()`): abajo de eso, la lista se recorre con la vista y enfocar solo
// serviría para levantar el teclado del tablet.
const MIN_OPTIONS_TO_FOCUS_FILTER = 8

// Aire entre el panel y el borde que lo recorta, para que no quede pegado.
const EDGE_MARGIN = 8

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
    this.position()
    this.index = -1
    this.buttonTarget.setAttribute("aria-expanded", "true")
    if (this.filterableValue && this.hasFilterTarget) {
      this.filterTarget.value = ""
      this.applyFilter("")
      // Solo se enfoca el campo de filtro si la lista es larga: en tablet,
      // enfocarlo levanta el teclado en pantalla y tapa la mitad del panel —
      // absurdo para un combo de tres opciones (proveedor, marca).
      if (this.optionItems.length > MIN_OPTIONS_TO_FOCUS_FILTER) this.filterTarget.focus()
    }
  }

  close() {
    this.panelTarget.hidden = true
    this.index = -1
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.focusHost.removeAttribute("aria-activedescendant")
  }

  // Decide si el panel se abre hacia abajo o hacia arriba, y lo acota al
  // espacio que realmente hay.
  //
  // Hace falta porque el panel es `absolute`: no ocupa lugar en el flujo, así
  // que la página no crece para hacerle sitio, y el shell del sitio tiene
  // `overflow-hidden` (contiene el patrón de herramientas). El combo de
  // "Dividir facturas" es el último campo del paso 1 y su panel terminaba
  // 90 px por debajo del borde del shell: los dos montos más altos quedaban
  // cortados, sin scroll con el que llegar a ellos.
  //
  // Se resuelve aquí y no quitando el `overflow-hidden` porque esto sirve para
  // CUALQUIER combo que quede bajo en la pantalla — en una tablet apaisada,
  // eso incluye a casi todos.
  position() {
    const panel = this.panelTarget
    panel.classList.remove("bottom-full", "mb-1")
    panel.classList.add("top-full", "mt-1")
    panel.style.maxHeight = ""

    const button = this.buttonTarget.getBoundingClientRect()
    const limit  = this.clippingBounds
    const below  = limit.bottom - button.bottom - EDGE_MARGIN
    const above  = button.top - limit.top - EDGE_MARGIN
    const needed = panel.scrollHeight

    // Solo se voltea si arriba hay MÁS espacio, no apenas con que abajo falte:
    // en una pantalla muy baja ninguna dirección alcanza y abrir hacia arriba
    // tapaba el campo que se estaba llenando.
    const flip = needed > below && above > below
    if (flip) {
      panel.classList.remove("top-full", "mt-1")
      panel.classList.add("bottom-full", "mb-1")
    }

    // El tope inline solo se pone cuando el espacio es MENOR que el contenido;
    // si no, mandaría sobre el `max-h-72` de la clase y agrandaría el panel.
    const space = flip ? above : below
    if (needed > space) panel.style.maxHeight = `${Math.max(space, 0)}px`
  }

  // El borde real contra el que se recorta el panel: el primer ancestro que
  // no deja desbordar, o el viewport si no hay ninguno.
  get clippingBounds() {
    let node = this.panelTarget.parentElement
    while (node && node !== document.body) {
      const style = getComputedStyle(node)
      if (style.overflow !== "visible" || style.overflowY !== "visible") {
        const rect = node.getBoundingClientRect()
        return { top: Math.max(rect.top, 0), bottom: Math.min(rect.bottom, window.innerHeight) }
      }
      node = node.parentElement
    }
    return { top: 0, bottom: window.innerHeight }
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
    this.clearInvalid()
    this.close()
    this.buttonTarget.focus()
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // Tras un submit inválido, el combo queda con anillo rojo. Al elegir un
  // valor el anillo se quedaba puesto y el banner "Faltan datos obligatorios"
  // intacto: el capturista corregía, veía todo igual de rojo, dudaba si se
  // había guardado y volvía a abrir el combo a verificar. Con `cfdi-default`
  // el efecto se duplicaba — elegir la razón social auto-llena el uso de CFDI,
  // así que los DOS campos quedaban llenos y los dos seguían marcados.
  //
  // El banner se esconde cuando ya no queda ningún campo marcado; el servidor
  // vuelve a pintarlo tal cual si el siguiente envío sigue incompleto.
  clearInvalid() {
    if (this.inputTarget.value === "") return

    this.buttonTarget.classList.remove("ring-2", "ring-red-500")

    const form = this.element.closest("form")
    if (!form || form.querySelector(".ring-red-500")) return

    form.querySelector("[data-missing-fields]")?.classList.add("hidden")
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
