require "net/http"
require "json"

module Sync
  # Transmite los pedidos capturados offline al ERP, vía `POST /pedidos` de
  # rueda-api. Cada pedido enviado recibe su folio del ERP (`clave_pedido`),
  # que se guarda en `erp_folio` + se marca `transmitted_at`.
  #
  # Idempotente por diseño: solo toma pedidos `submitted` sin `erp_folio`, y el
  # endpoint del ERP no duplica un pedido ya insertado (PK de negocio). Un
  # reintento tras una caída retoma justo lo que faltó.
  class Up
    def initialize(api_base)
      root = api_base.end_with?("/") ? api_base : "#{api_base}/"
      @endpoint = URI.join(root, "pedidos")
    end

    def run!
      results = { transmitted: [], failed: [] }

      pending.find_each do |order|
        res = post(build_payload(order))
        if res.is_a?(Net::HTTPSuccess)
          folio = JSON.parse(res.body)["clave_pedido"]
          order.update!(erp_folio: folio, transmitted_at: Time.current)
          results[:transmitted] << { local: order.local_folio, erp: folio }
        else
          msg = parse_error(res)
          results[:failed] << { local: order.local_folio, status: res.code, error: msg }
        end
      end

      results
    end

    private

    def pending
      Order.submitted.where(erp_folio: nil)
           .includes(:user, :order_items, :client_tax_profile, :cfdi_use,
                     :client_branch, client: :salesperson)
    end

    def build_payload(order)
      # Hora local de captura (el ERP maneja horas locales; created_at es UTC).
      captured = order.created_at.localtime

      {
        capturista_erp_person_id: order.user.erp_person_id,
        clave_cliente: order.client.erp_client_key,
        fecha_pedido:  captured.strftime("%Y-%m-%d"),
        hora_pedido:   captured.strftime("%H:%M:%S"),
        remision:      order.remission?,
        rfc:           order.client_tax_profile&.rfc,
        c_UsoCFDI:     order.cfdi_use&.code,
        sucursal:      order.client_branch&.erp_branch_id,
        id_vendedor:   order.client.salesperson&.erp_salesperson_id,
        observaciones: order.observations,
        subtotal:      order.subtotal,
        descto_monto:  order.discount_total,
        iva_monto:     order.tax_total,
        total:         order.total,
        items: order.order_items.map.with_index(1) do |it, i|
          {
            consecutivo:       i,
            id_producto:       it.product&.erp_product_id,
            cantidad:          it.quantity,
            precio:            it.unit_price,
            subtotal:          it.line_total,
            descto_porcentaje: it.discount_percent,
            descto_monto:      it.discount_amount,
            iva_porcentaje:    it.tax_rate,
            iva_monto:         it.tax_amount,
            total:             it.total
          }
        end
      }
    end

    def post(payload)
      http = Net::HTTP.new(@endpoint.host, @endpoint.port)
      req  = Net::HTTP::Post.new(@endpoint, "Content-Type" => "application/json")
      req.body = payload.to_json
      http.request(req)
    end

    def parse_error(res)
      JSON.parse(res.body)["message"]
    rescue StandardError
      res.body.to_s[0, 200]
    end
  end
end
