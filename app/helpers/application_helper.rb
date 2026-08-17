module ApplicationHelper
  # Enlace de regreso a la pantalla anterior ("← Volver a …"), alineado a la
  # derecha del encabezado. Es NAVEGACIÓN, no acción: por eso va en el
  # secundario sobre fondo oscuro (`bg-white/10`) y más ligero que los botones
  # de la barra, que sí son acciones.
  #
  # Vive aquí y no copiado en cada vista porque el detalle del pedido se había
  # quedado con el estilo de acción (`bg-neutral-700`, `font-bold`) y nadie lo
  # notaba: la única forma de que un estándar se sostenga es que tenga un solo
  # lugar donde cambiarlo.
  BACK_LINK_CLASS = "rounded-full bg-white/10 px-5 py-2.5 text-sm font-semibold " \
                    "text-white transition-colors hover:bg-white/20".freeze

  # La receta ÚNICA de los formularios de campo por partida (hasta 5 por fila
  # del genérico): un solo lugar para el binding de submit-end — el revert de
  # la pausa hubo que añadirlo 4 veces a mano cuando la receta vivía copiada
  # en cada celda (6ª auditoría).
  def item_field_form(order, item, suffix, &block)
    form_with model: item, url: order_order_item_path(order, item), method: :patch,
              id: dom_id(item, :"#{suffix}_form"),
              data: { controller: "form-submit",
                      action: "turbo:submit-end->form-submit#flashStatus" }, &block
  end

  def back_link_class
    BACK_LINK_CLASS
  end
end
