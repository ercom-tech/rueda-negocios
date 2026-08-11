import { Controller } from "@hotwired/stimulus"

// Manda el foco a un elemento cuando una respuesta Turbo lo pide.
//
// Existe porque hay acciones que DESTRUYEN el elemento que tenía el foco: al
// quitar una partida, el botón que abrió el modal se va con su fila y el foco
// cae al <body> — quien navega con teclado tiene que retabular desde el inicio
// de la página en cada baja.
//
// El truco es que el servidor reemplace (no morphee) un elemento vacío que
// lleva este controller: al insertarse, Stimulus lo conecta y aquí se mueve el
// foco. Con morph el nodo se conserva y `connect()` no volvería a correr.
//
// Uso: turbo_stream.replace("focus-director", partial que renderiza
//   <span data-controller="focus" data-focus-selector-value="#lo-que-sea">
export default class extends Controller {
  static values = { selector: String }

  connect() {
    const target = document.querySelector(this.selectorValue)
    // Un campo deshabilitado (p.ej. el buscador al llegar al tope de partidas)
    // ignora `focus()`: no hay nada que hacer y tampoco estorba.
    target?.focus()
  }
}
