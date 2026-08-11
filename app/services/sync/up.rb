require "net/http"
require "json"

module Sync
  # Transmite los pedidos capturados offline al ERP, vía `POST /pedidos` de
  # rueda-api. Cada pedido enviado recibe su folio del ERP (`clave_pedido`),
  # que se guarda en `erp_folio` + se marca `transmitted_at`.
  #
  # Idempotente por diseño: solo toma pedidos `captured` sin `erp_folio`, y el
  # endpoint del ERP no duplica un pedido ya insertado (PK de negocio). Un
  # reintento tras una caída retoma justo lo que faltó.
  class Up
    # Se levanta cuando la guarda impide transmitir (hay pedidos en borrador).
    class GuardError < StandardError; end

    # Transmitir con borradores vivos deja al operador creyendo que ya todo
    # llegó al ERP (el sync-up solo toma `captured`) — y el paso siguiente,
    # cerrar la rueda, los purga. Método de clase para que el controlador
    # pueda preguntarlo ANTES de crear el SyncRun (una condición previa no
    # debe quedar registrada como una corrida fallida); `run!` lo repite para
    # cubrir `rake sync:up`. Regla compartida con el sync-down (Sync::Guards).
    def self.guard!
      Guards.no_draft_orders!(GuardError)
    end

    def initialize(api_base = ENV["RUEDA_API_URL"])
      raise Sync::ApiClient::Error, "RUEDA_API_URL no configurada" if api_base.to_s.strip.empty?

      root = api_base.end_with?("/") ? api_base : "#{api_base}/"
      @endpoint = URI.join(root, "pedidos")
    end

    def run!
      self.class.guard!
      results = { transmitted: [], failed: [] }

      pending.find_each do |order|
        res = post(build_payload(order))
        if res.is_a?(Net::HTTPSuccess)
          folio = JSON.parse(res.body)["clave_pedido"]
          # Un 2xx sin folio es una respuesta rota: marcarlo transmitido con
          # erp_folio nil lo atascaría para siempre (pending solo re-selecciona
          # captured). Mejor fallido y reintentable.
          raise ApiClient::Error, "respuesta sin clave_pedido" if folio.to_s.strip.empty?

          order.update!(erp_folio: folio, transmitted_at: Time.current, status: :transmitted)
          results[:transmitted] << { local: order.local_folio, erp: folio }
        else
          msg = parse_error(res)
          results[:failed] << { local: order.local_folio, status: res.code, error: msg }
        end
      rescue SystemCallError, SocketError, Timeout::Error, Net::ReadTimeout,
             JSON::ParserError, ApiClient::Error, ActiveRecord::ActiveRecordError => e
        # Un error de red, una respuesta rota (200 no-JSON, 200 sin folio) o un
        # fallo al guardar el folio localmente no abortan la transmisión: se
        # marca fallido ESE pedido y el lote sigue (el sync-up es reintentable).
        # Sin `ActiveRecordError` en la lista, un `update!` que fallara sacaba
        # la excepción del `find_each` y los pedidos restantes ni se intentaban,
        # con el primero ya insertado en el ERP.
        results[:failed] << { local: order.local_folio, status: "—", error: e.message }
      end

      results
    end

    private

    def pending
      Order.captured.where(erp_folio: nil)
           .includes(:user, { order_items: :product }, :client_tax_profile, :cfdi_use,
                     :client_receipt_profile, :client_branch, client: :salesperson)
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
        # A nombre de quién va la remisión. Es el consecutivo del perfil en el
        # ERP (vta_cliente_has_remision) y de él cuelga la cuenta referenciada
        # de cobranza: sin él, la remisión queda sin destinatario — el capturista
        # lo elige en el paso 1 y hasta ahora se quedaba en la laptop.
        # Atado al tipo de pedido y no solo al dato guardado: una factura lo
        # lleva en 0 (243,318 de 243,334 en el ERP), y los pedidos capturados
        # antes de que el encabezado limpiara su rama inactiva pueden traerlo.
        consec_remision: (order.client_receipt_profile&.erp_receipt_profile_id if order.remission?),
        sucursal:      order.client_branch&.erp_branch_id,
        id_vendedor:   order.client.salesperson&.erp_salesperson_id,
        observaciones: order.observations,
        # Como consec_remision, atado al tipo y no solo al dato guardado: es
        # campo de factura, y los pedidos capturados antes de que el encabezado
        # limpiara su rama inactiva pueden traer un monto que ya no se muestra.
        dividir_facturas: (order.dividir_facturas if order.invoice?) || 0,
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
      http.open_timeout = ApiClient::OPEN_TIMEOUT
      http.read_timeout = ApiClient::READ_TIMEOUT
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
