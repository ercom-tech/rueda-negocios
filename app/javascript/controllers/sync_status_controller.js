import { Controller } from "@hotwired/stimulus"

// Mantiene al día el menú del servidor SIN depender del WebSocket.
//
// El broadcast de SyncRun es el camino rápido, pero se pierde en un caso muy
// común: al lanzar un sync el controlador responde con un redirect, el
// navegador navega, y esa navegación tira la suscripción de Action Cable
// mientras abre otra. Una corrida que termina en menos de un segundo emite su
// broadcast en ese hueco y nadie lo oye — el panel se queda en "en progreso"
// para siempre y solo recargar lo destraba.
//
// Uso: data-controller="sync-status" con
//   data-sync-status-url-value="/server/menu"
//   data-sync-status-busy-value="true"   (hay una corrida viva)
//
// Va en el partial que se reemplaza, así que cada actualización vuelve a
// conectar este controller con el `busy` nuevo: si la corrida terminó, el
// sondeo no se reanuda.
export default class extends Controller {
  static values = {
    url: String,
    busy: Boolean,
    // Cada cuánto preguntar mientras hay corrida viva. 3 s es suficiente para
    // que se sienta inmediato sin castigar a la laptop, que además está
    // sirviendo la captura de todo el salón.
    interval: { type: Number, default: 3000 }
  }

  // Solo se sondea con una corrida viva, y eso NO es una optimización: cada
  // respuesta reemplaza este div y reconecta el controller, así que un refresh
  // incondicional en connect() se realimentaría en un bucle infinito de
  // peticiones. Con la condición, la cadena termina sola: el estado nuevo
  // llega con busy=false y ahí se para.
  //
  // Cubre igual el caso que lo motiva, porque el panel se renderiza CON la
  // corrida viva (es lo que muestra "en progreso"): sondea hasta verla cerrada.
  connect() {
    if (this.busyValue) this.start()
  }

  disconnect() {
    this.stop()
  }

  start() {
    this.stop()
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  async refresh() {
    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" }
      })
      if (!res.ok) return

      // Turbo aplica el stream: reemplaza #server-menu y, con él, este mismo
      // controller. Si la corrida ya terminó, el nodo nuevo llega con
      // busy=false y el sondeo no arranca de nuevo.
      window.Turbo.renderStreamMessage(await res.text())
    } catch {
      // Sin red o servidor caído: se calla y reintenta al siguiente tick. El
      // panel se queda con lo último bueno, que es mejor que un error encima
      // de la pantalla de operación.
    }
  }
}
