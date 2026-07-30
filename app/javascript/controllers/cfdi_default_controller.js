import { Controller } from "@hotwired/stimulus"

// Al elegir la razón social (perfil fiscal) en el paso 1, sincroniza el combo
// de Uso de CFDI con el default que ese perfil trae configurado en el ERP.
// Uso: data-controller="cfdi-default" en el <form>, con
//   data-cfdi-default-map-value = {"<tax_profile_id>": cfdi_use_id, ...}
//   data-cfdi-default-target="cfdi" en el wrapper del custom_select de CFDI
//   y el hidden del perfil con data-action="change->cfdi-default#apply".
export default class extends Controller {
  static targets = ["cfdi"]
  static values = { map: Object }

  apply(event) {
    const cfdiId = this.mapValue[event.target.value]
    if (!cfdiId || !this.hasCfdiTarget) return

    // Reutiliza la lógica del select (label, aria-selected, change) haciendo
    // click en la opción correspondiente del combo de CFDI.
    this.cfdiTarget.querySelector(`button[data-value="${cfdiId}"]`)?.click()
  }
}
