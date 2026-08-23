class Promotion < ApplicationRecord
  # Promoción de la rueda (vta_promocion con canal_venta = 'RUN'), espejo de
  # lo que el ERP configuró para el evento. Se repuebla en cada sync-down.
  #
  # El modelo completo, y por qué está así, en docs/erp-esquema-promociones.md.
  # Lo esencial para leer este archivo:
  #
  #   - El universo (`promotion_products`) es una lista EXPLÍCITA y curada por
  #     el ERP, no el resultado de un criterio: MAKITA participa con 2,134 de
  #     los 2,209 productos de su proveedor. No se re-deriva.
  #   - El descuento es del GRUPO, no de la partida: el escalón se elige con
  #     la suma de todas las partidas del pedido que están en el universo.
  #   - Una partida participa en una sola promoción, y un pedido puede aplicar
  #     varias entre sus partidas.

  has_many :promotion_tiers,   -> { order(:erp_consecutive) }, dependent: :destroy
  has_many :promotion_products, dependent: :destroy
  has_many :products, through: :promotion_products

  validates :erp_promotion_id, presence: true, uniqueness: true

  # Vigente en una fecha (la de captura del pedido — decisión del usuario
  # 2026-08-22). Las 38 de la rueda arrancan escalonadas entre el 15 y el 22
  # de agosto, así que "vigente hoy" no es "vigente durante la rueda".
  scope :effective_on, ->(date) {
    where(starts_on: ..date).where(ends_on: date..)
  }

  # La promoción de un producto en una fecha, o nil. Un producto está hoy en
  # una sola promoción de la rueda (verificado sobre los 6,046 del ERP), pero
  # eso es dato del ERP y puede cambiar: se toma la de menor erp_promotion_id
  # para que la elección sea estable entre repintados, y el panel del servidor
  # avisa cuando el sync-down detecta un producto en dos
  # (`shared_promotion_products`).
  def self.for_product(product, on:)
    return nil if product.nil?

    effective_on(on).joins(:promotion_products)
                    .where(promotion_products: { product_id: product.id })
                    .order(:erp_promotion_id).first
  end

  # { product_id => Promotion } para un conjunto de productos, en UNA consulta.
  #
  # `for_product` por separado eran 45 consultas idénticas por repintado —una
  # por partida— y ocurre en cada alta, baja y cambio de cantidad, desde una
  # tablet (7ª auditoría). Mismo desempate que `for_product`: el menor
  # `erp_promotion_id` gana, para que la elección sea estable entre pintados.
  def self.index_by_product(product_ids, on:)
    return {} if product_ids.blank?

    # Orden descendente + `to_h`: la última escritura de cada producto gana, o
    # sea la del erp_promotion_id MENOR — el mismo desempate que `for_product`.
    pairs = effective_on(on).joins(:promotion_products)
                            .where(promotion_products: { product_id: product_ids })
                            .order(erp_promotion_id: :desc)
                            .pluck("promotion_products.product_id", :id)
                            .to_h
    by_id = where(id: pairs.values.uniq).index_by(&:id)
    pairs.transform_values { |promotion_id| by_id[promotion_id] }
  end

  # Override del producto dentro de esta promoción, o nil si no tiene.
  # Gana sobre el escalón: FANAL lleva su único escalón en 0% y el descuento
  # real (10% o 20%) en cada uno de sus 57 códigos.
  def override_for(product)
    percent = promotion_products.find_by(product_id: product&.id)&.discount_percent
    percent if percent&.positive?
  end

  # Escalón que corresponde a un acumulado, o nil si todavía no alcanza.
  #
  # Desempate por `quantity_from` descendente, NO por consecutivo: FANDELI
  # trae dos escalones abiertos traslapados (≥15,000 → 9% y ≥20,000 → 9% +
  # regalo) y con "el primero que empata" un pedido de $25,000 se quedaba sin
  # el regalo que el proveedor prometió.
  def tier_for(amount)
    promotion_tiers.select { |tier| tier.covers?(amount) }
                   .max_by(&:quantity_from)
  end

  # Unidad en la que se mide el acumulado. Los escalones de una promoción
  # siempre comparten unidad en el ERP; si alguna llegara mezclada, manda el
  # primero (el de menor consecutivo) para no medir con dos varas.
  def unit
    promotion_tiers.first&.unit
  end

  def measured_in_money?
    unit == "MXN"
  end

  def effective_on?(date)
    return false if starts_on.nil? || ends_on.nil?

    date >= starts_on && date <= ends_on
  end
end
