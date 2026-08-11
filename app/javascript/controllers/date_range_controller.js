import { Controller } from "@hotwired/stimulus"

// Selector de RANGO de fechas en un solo control: un pill abre un panel con el
// calendario de un mes y el rango se marca ahí mismo. Escribe dos inputs
// hidden (from/to) y dispara "change" en ellos al completarse, para que el
// formulario de filtros se envíe solo, igual que los combos.
//
// Dos gestos, a propósito: en escritorio se puede ARRASTRAR (mousedown en el
// día inicial, preview al pasar por encima, mouseup cierra el rango) y en
// tablet CLIC-CLIC (primer clic fija el inicio, segundo el fin) — arrastrar en
// pantalla táctil es incómodo y los capturistas usan tablet.
//
// Un mes a la vez: dos meses no caben en una tablet en vertical.
//
// Uso: data-controller="date-range" con targets button/label/panel/grid/title
// y los hidden from/to; data-action="click@window->date-range#hide".
const DIAS  = ["L", "M", "M", "J", "V", "S", "D"]
const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
               "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

export default class extends Controller {
  static targets = ["button", "label", "panel", "grid", "title", "from", "to"]

  connect() {
    this.start = this.parse(this.fromTarget.value)
    this.end   = this.parse(this.toTarget.value)
    this.today = this.stripTime(new Date())
    // Sin rango elegido, el calendario abre en el mes de HOY.
    this.cursor = new Date(this.start || this.today)
    this.cursor.setDate(1)
    this.dragging = false
    this.paintLabel()
  }

  // --- Panel --------------------------------------------------------------

  toggle(event) {
    event.preventDefault()
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.buildGrid()
  }

  close() {
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.dragging = false
  }

  // Clic afuera (el @window del data-action). Ignora los clics dentro.
  hide(event) {
    if (this.element.contains(event.target)) return

    this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }

  prevMonth(event) {
    event.preventDefault()
    this.cursor.setMonth(this.cursor.getMonth() - 1)
    this.buildGrid()
  }

  nextMonth(event) {
    event.preventDefault()
    this.cursor.setMonth(this.cursor.getMonth() + 1)
    this.buildGrid()
  }

  // --- Selección ----------------------------------------------------------

  // mousedown: arranca el rango (y el posible arrastre).
  pickStart(event) {
    const dia = this.dayFrom(event)
    if (!dia) return

    event.preventDefault()
    // Rango completo + clic nuevo = empezar de cero. Con solo inicio, el
    // segundo clic cierra el rango (gesto clic-clic de tablet).
    if (this.start && !this.end) {
      this.commit(this.start, dia)
      return
    }
    this.start = dia
    this.end = null
    this.dragging = true
    this.paint()
  }

  // Arrastre: preview del rango mientras el mouse pasa por los días.
  preview(event) {
    if (!this.dragging) return

    const dia = this.dayFrom(event)
    if (!dia) return

    this.hover = dia
    this.paint()
  }

  // mouseup sobre un día: cierra el rango (gesto de arrastre).
  pickEnd(event) {
    if (!this.dragging) return

    const dia = this.dayFrom(event)
    if (!dia) return
    // Un mousedown+mouseup en el MISMO día no cierra el rango: es un clic, y
    // se espera el segundo (si no, no habría manera de elegir un rango de un
    // solo día distinto al de un clic accidental).
    if (this.sameDay(dia, this.start)) {
      this.dragging = false
      this.hover = null
      this.paint()
      return
    }
    this.commit(this.start, dia)
  }

  clear(event) {
    event.preventDefault()
    this.start = null
    this.end = null
    this.hover = null
    this.write()
    this.close()
  }

  commit(a, b) {
    const [ini, fin] = a <= b ? [a, b] : [b, a]
    this.start = ini
    this.end = fin
    this.dragging = false
    this.hover = null
    this.write()
    this.close()
  }

  // Escribe los hidden y avisa al formulario (filtra al seleccionar).
  write() {
    this.fromTarget.value = this.format(this.start)
    this.toTarget.value = this.format(this.end)
    this.paint()
    this.fromTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // --- Render -------------------------------------------------------------
  // El grid se CONSTRUYE solo al abrir o al cambiar de mes; la selección solo
  // repinta clases. Reconstruirlo en cada movimiento destruía el botón bajo el
  // cursor, y como Stimulus enlaza las acciones de los nodos nuevos de forma
  // asíncrona, el clic siguiente caía en un botón sin acción: el segundo día
  // del rango no se registraba.

  buildGrid() {
    this.titleTarget.textContent = `${MESES[this.cursor.getMonth()]} ${this.cursor.getFullYear()}`
    this.gridTarget.innerHTML = ""
    DIAS.forEach((d) => {
      const th = document.createElement("span")
      th.textContent = d
      th.className = "py-1 text-center text-xs font-semibold text-neutral-500"
      this.gridTarget.appendChild(th)
    })
    // Lunes primero: getDay() es 0=domingo.
    const hueco = (new Date(this.cursor).getDay() + 6) % 7
    for (let i = 0; i < hueco; i++) this.gridTarget.appendChild(document.createElement("span"))

    const ultimo = new Date(this.cursor.getFullYear(), this.cursor.getMonth() + 1, 0).getDate()
    for (let d = 1; d <= ultimo; d++) {
      const fecha = new Date(this.cursor.getFullYear(), this.cursor.getMonth(), d)
      const btn = document.createElement("button")
      btn.type = "button"
      btn.textContent = d
      btn.dataset.date = this.format(fecha)
      btn.dataset.action = "mousedown->date-range#pickStart mouseenter->date-range#preview mouseup->date-range#pickEnd"
      this.gridTarget.appendChild(btn)
    }
    this.paint()
  }

  paint() {
    this.paintLabel()
    if (this.panelTarget.hidden) return

    const fin = this.end || (this.dragging ? this.hover : null)
    const [a, b] = this.start && fin && this.start > fin ? [fin, this.start] : [this.start, fin]

    this.gridTarget.querySelectorAll("[data-date]").forEach((btn) => {
      const fecha = this.parse(btn.dataset.date)
      // El día bajo el cursor cuenta como extremo mientras se arrastra: si no,
      // el día donde vas a soltar se queda sin marcar y el preview se ve corto.
      const extremo = this.sameDay(fecha, this.start) || this.sameDay(fecha, this.end) ||
                      (this.dragging && this.sameDay(fecha, this.hover))
      const dentro  = a && b && fecha > a && fecha < b
      // Hoy siempre marcado (anillo), aunque no sea parte del rango: es la
      // referencia para ubicarse en el calendario.
      const hoy = this.sameDay(fecha, this.today)

      btn.className = "h-9 rounded-lg text-sm font-semibold transition-colors " +
        (extremo ? "bg-brand-coral text-white"
                 : dentro ? "bg-brand-gold text-neutral-900"
                          : "text-neutral-900 hover:bg-black/5") +
        (hoy && !extremo ? " ring-2 ring-inset ring-brand-coral" : "")
      btn.setAttribute("aria-current", hoy ? "date" : "false")
    })
  }

  paintLabel() {
    this.labelTarget.textContent = this.summary()
    this.labelTarget.classList.toggle("text-white/60", !this.start)
  }

  summary() {
    if (!this.start) return this.element.dataset.placeholder || "Fecha crea"
    if (!this.end) return `${this.short(this.start)} — …`
    // Rango de un solo día: se muestra una sola fecha, no "X — X".
    if (this.sameDay(this.start, this.end)) return this.short(this.start)

    return `${this.short(this.start)} — ${this.short(this.end)}`
  }

  // --- Utilidades de fecha ------------------------------------------------
  // Todo en fecha LOCAL (nunca `new Date("2026-08-10")`, que se interpreta
  // como UTC y en México adelanta un día).

  dayFrom(event) {
    const iso = event.target.dataset?.date
    return iso ? this.parse(iso) : null
  }

  parse(iso) {
    if (!iso) return null

    const [y, m, d] = iso.split("-").map(Number)
    return new Date(y, m - 1, d)
  }

  format(fecha) {
    if (!fecha) return ""

    return [fecha.getFullYear(), fecha.getMonth() + 1, fecha.getDate()]
      .map((n, i) => String(n).padStart(i === 0 ? 4 : 2, "0")).join("-")
  }

  short(fecha) {
    return `${String(fecha.getDate()).padStart(2, "0")}/${String(fecha.getMonth() + 1).padStart(2, "0")}/${fecha.getFullYear()}`
  }

  sameDay(a, b) {
    return !!a && !!b && a.getTime() === b.getTime()
  }

  stripTime(fecha) {
    return new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate())
  }
}
