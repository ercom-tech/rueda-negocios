import { Controller } from "@hotwired/stimulus"

// Barra fija con los totales del pedido, al pie de la pantalla, que aparece
// SOLO cuando la tarjeta de totales no se ve completa.
//
// Nació de un pedido del evento: con muchas partidas, para ver los totales
// había que bajar hasta el final. La primera idea —repetir la tarjeta en el
// encabezado— resolvía ese caso pero duplicaba los cuatro importes en la misma
// pantalla cuando hay pocas partidas. Así nunca se ven dos veces: con pocas
// partidas la tarjeta ya está a la vista y la barra no aparece.
//
// Se observa la tarjeta y no la posición del scroll: la tabla cambia de alto
// con cada alta (y el morph la repinta), y lo único que importa es si la
// tarjeta está en pantalla, que es justo lo que dice IntersectionObserver.
export default class extends Controller {
  static targets = ["bar", "card"]

  // La tarjeta ENTERA: con solo el Subtotal asomando, el Total no se ve.
  static FULLY_VISIBLE = 0.99

  disconnect() {
    this._observer?.disconnect()
    this._observer = null
    this.reservePageSpace(false)
  }

  // La tarjeta se repinta con morph, que conserva el nodo; pero si algún día
  // se reemplazara, Stimulus la vuelve a conectar como target y la
  // observación sigue sin que nada se entere.
  cardTargetConnected(card) {
    this.observer.observe(card)
  }

  cardTargetDisconnected(card) {
    this._observer?.unobserve(card)
  }

  // Perezoso y no en connect(): Stimulus puede avisar de los targets ANTES
  // de connect(), y un observador que todavía no existe dejaría la tarjeta
  // sin observar — la barra no aparecería nunca, sin error.
  get observer() {
    this._observer ??= new IntersectionObserver(
      ([entry]) => this.toggle(entry),
      { threshold: [0, this.constructor.FULLY_VISIBLE] }
    )
    return this._observer
  }

  toggle(entry) {
    this.barTarget.hidden = entry.isIntersecting && entry.intersectionRatio >= this.constructor.FULLY_VISIBLE
    this.reservePageSpace(!this.barTarget.hidden)
  }

  // Mientras la barra se ve, la página reserva abajo su alto
  // (`scroll-padding-bottom`): el navegador lo descuenta al llevar algo a la
  // vista —el renglón recién agregado (`scroll-to`), y el campo al que se
  // llega con Tab—, así que lo deja ARRIBA de la barra y no debajo. Sin esto,
  // en tablet horizontal la barra tapaba la Cantidad del renglón nuevo en cada
  // alta (12ª auditoría).
  reservePageSpace(reserve) {
    document.documentElement.style.scrollPaddingBottom = reserve ? `${this.barTarget.offsetHeight}px` : ""
  }

  // Tocar la barra lleva a la tarjeta completa, con descuento e IVA. El foco
  // va a la tarjeta: la barra se oculta con el foco adentro, y sin esto caía
  // al <body> y el siguiente Tab empezaba desde arriba de la página.
  reveal() {
    const smooth = !window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.cardTarget.focus({ preventScroll: true })
    this.cardTarget.scrollIntoView({ behavior: smooth ? "smooth" : "auto", block: "end" })
  }
}
