import { Controller } from "@hotwired/stimulus"

// Anula el envío implícito (Enter) de un formulario que SOLO debe enviarse
// confirmando en su modal — el paso 1 de "Convertir en pedido" de una
// cotización genérica (19ª auditoría).
//
// Ahí el único submit del formulario es el "Sí, convertir" del diálogo
// oculto, y Enter sobre el radio Factura/Remisión hacía el envío implícito
// por él: convertía sin modal. Un botón predeterminado deshabilitado delante
// NO sirve: Chrome lo salta y usa el siguiente habilitado (medido).
//
// Enter se respeta donde tiene trabajo propio: un textarea (salto de línea),
// un botón o un enlace (activarlo), y lo que ya lo atendió (el filtro de un
// combo hace preventDefault antes de que el evento suba hasta aquí).
export default class extends Controller {
  block(event) {
    if (event.key !== "Enter" || event.defaultPrevented) return
    if (event.target.closest("textarea, button, a")) return

    event.preventDefault()
  }
}
