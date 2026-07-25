import { Controller } from "@hotwired/stimulus"

// Muestra/oculta los campos de Factura (uso CFDI + razón social) vs Remisión
// según el radio seleccionado. Uso: data-controller="order-kind" en el <form>,
// data-action="change->order-kind#toggle" en los radios, y
// data-order-kind-target="invoice|remission" en los grupos de campos.
export default class extends Controller {
  static targets = ["invoice", "remission"]

  connect() { this.toggle() }

  toggle() {
    const kind = this.element.querySelector('input[name="order[kind]"]:checked')?.value
    const invoice = kind !== "remission"
    this.invoiceTargets.forEach((el) => el.classList.toggle("hidden", !invoice))
    this.remissionTargets.forEach((el) => el.classList.toggle("hidden", invoice))
  }
}
