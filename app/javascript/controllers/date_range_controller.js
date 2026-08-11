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
    // Una selección a medias se descarta al cerrar. Si sobrevive, el control
    // sigue mostrando "10/08/2026 — …" aunque NUNCA se filtró, y al reabrirlo
    // el primer toque cierra el rango contra una fecha que el usuario ya
    // olvidó: los importes cambian sin explicación.
    if (this.start && !this.end) {
      this.start = null
      this.hover = null
      this.paintLabel()
    }
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
    const day = this.dayFrom(event)
    if (!day) return

    event.preventDefault()
    // Rango completo + clic nuevo = empezar de cero. Con solo inicio, el
    // segundo clic cierra el rango (gesto clic-clic de tablet).
    if (this.start && !this.end) {
      this.commit(this.start, day)
      return
    }
    this.start = day
    this.end = null
    this.dragging = true
    this.paint()
  }

  // Arrastre: preview del rango mientras el mouse pasa por los días.
  preview(event) {
    if (!this.dragging) return

    const day = this.dayFrom(event)
    if (!day) return

    this.hover = day
    this.paint()
  }

  // mouseup sobre un día: cierra el rango (gesto de arrastre).
  pickEnd(event) {
    if (!this.dragging) return

    const day = this.dayFrom(event)
    if (!day) return
    // Un mousedown+mouseup en el MISMO día no cierra el rango: es un clic, y
    // se espera el segundo (si no, no habría manera de elegir un rango de un
    // solo día distinto al de un clic accidental).
    if (this.sameDay(day, this.start)) {
      this.dragging = false
      this.hover = null
      this.paint()
      return
    }
    this.commit(this.start, day)
  }

  // Activación por TECLADO (Enter/Espacio). El navegador manda `click` con
  // detail = 0 cuando viene del teclado y > 0 cuando viene del mouse: así se
  // ignora el click que sigue a un clic real, ya atendido por
  // pickStart/pickEnd.
  pickByKeyboard(event) {
    if (event.detail > 0) return // vino del mouse: ya lo atendieron pickStart/pickEnd

    this.pick(event)
  }

  pick(event) {
    const day = this.dayFrom(event)
    if (!day) return

    // Primer toque fija el inicio; el segundo cierra el rango (el mismo día
    // dos veces = rango de un día).
    if (this.start && !this.end) return this.commit(this.start, day)

    this.start = day
    this.end = null
    this.paint()
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
    const [first, last] = a <= b ? [a, b] : [b, a]
    this.start = first
    this.end = last
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
    const blanks = (new Date(this.cursor).getDay() + 6) % 7
    for (let i = 0; i < blanks; i++) this.gridTarget.appendChild(document.createElement("span"))

    const lastDay = new Date(this.cursor.getFullYear(), this.cursor.getMonth() + 1, 0).getDate()
    for (let d = 1; d <= lastDay; d++) {
      const date = new Date(this.cursor.getFullYear(), this.cursor.getMonth(), d)
      const btn = document.createElement("button")
      btn.type = "button"
      btn.textContent = d
      btn.dataset.date = this.format(date)
      // `click` además de los eventos de mouse: Enter y Espacio sobre un
      // <button> disparan click y NUNCA mousedown, así que sin esto el
      // calendario era inoperable con teclado (la laptop del servidor se usa
      // así). `pick` es idempotente con el gesto de arrastre, que ya cerró el
      // rango en su mouseup.
      btn.dataset.action = "mousedown->date-range#pickStart mouseenter->date-range#preview " +
                           "mouseup->date-range#pickEnd click->date-range#pickByKeyboard"
      this.gridTarget.appendChild(btn)
    }
    this.paint()
  }

  paint() {
    this.paintLabel()
    if (this.panelTarget.hidden) return

    const until = this.end || (this.dragging ? this.hover : null)
    const [a, b] = this.start && until && this.start > until ? [until, this.start] : [this.start, until]

    this.gridTarget.querySelectorAll("[data-date]").forEach((btn) => {
      const date = this.parse(btn.dataset.date)
      // El día bajo el cursor cuenta como extremo mientras se arrastra: si no,
      // el día donde vas a soltar se queda sin marcar y el preview se ve corto.
      const isEdge = this.sameDay(date, this.start) || this.sameDay(date, this.end) ||
                      (this.dragging && this.sameDay(date, this.hover))
      const isInside = a && b && date > a && date < b
      // Hoy siempre marcado (anillo), aunque no sea parte del rango: es la
      // referencia para ubicarse en el calendario.
      const isToday = this.sameDay(date, this.today)

      btn.className = "h-9 rounded-lg text-sm font-semibold transition-colors " +
        (isEdge ? "bg-brand-coral text-white"
                 : isInside ? "bg-brand-gold text-neutral-900"
                          : "text-neutral-900 hover:bg-black/5") +
        (isToday && !isEdge ? " ring-2 ring-inset ring-brand-coral" : "")
      btn.setAttribute("aria-current", isToday ? "date" : "false")
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

  format(date) {
    if (!date) return ""

    return [date.getFullYear(), date.getMonth() + 1, date.getDate()]
      .map((n, i) => String(n).padStart(i === 0 ? 4 : 2, "0")).join("-")
  }

  short(date) {
    return `${String(date.getDate()).padStart(2, "0")}/${String(date.getMonth() + 1).padStart(2, "0")}/${date.getFullYear()}`
  }

  sameDay(a, b) {
    return !!a && !!b && a.getTime() === b.getTime()
  }

  stripTime(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
  }
}
