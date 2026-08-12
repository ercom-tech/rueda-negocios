import { Controller } from "@hotwired/stimulus"

// Nodo efímero que viaja en la respuesta Turbo: al conectar, lleva la vista
// hasta el elemento indicado y se elimina. Nació para la partida recién
// agregada: en pedidos largos la fila nueva entraba abajo del pliegue, sin
// scroll ni realce, y la única señal de que "sí entró" era el contador — con
// prisa, la duda llevaba a re-agregar. No roba el foco (el buscador lo
// conserva para seguir capturando).
export default class extends Controller {
  static values = { anchor: String }

  connect() {
    document.getElementById(this.anchorValue)?.scrollIntoView({ behavior: "smooth", block: "nearest" })
    this.element.remove()
  }
}
