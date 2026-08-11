require "test_helper"

module Sync
  class CloseRoundTest < ActiveSupport::TestCase
    setup do
      @user   = User.create!(erp_person_id: 9301, username: "cap_cr", password: "x", role: "capturista")
      @round  = BusinessRound.create!(erp_round_id: 9301, name: "Rueda CR", active: true)
      @client = Client.create!(erp_client_key: "CR01", name: "Cliente CR")
      Setting.instance.update!(selected_round_erp_id: @round.erp_round_id,
                               selected_round_name: @round.name)
    end

    def order(status:, erp_folio: nil)
      Order.create!(user: @user, business_round: @round, client: @client,
                    kind: "remission", status: status, erp_folio: erp_folio,
                    local_folio: "RN-#{format('%06d', rand(1_000_000))}")
    end

    test "no cierra si hay pedidos capturados sin transmitir" do
      order(status: "captured")

      error = assert_raises(CloseRound::PendingOrdersError) { CloseRound.run! }
      assert_match(/Hay 1 pedido sin transmitir y se perdería al cerrar la rueda\./, error.message)
      assert_equal 1, Order.count, "no debe borrar nada"
      assert @round.reload.active?
    end

    # Cambio de criterio (2026-08-10): un borrador también bloquea. Cerrar
    # borra TODOS los pedidos locales, así que una captura en curso se perdía
    # en silencio. Misma guarda que "obtener información" (Guards).
    test "no cierra si hay pedidos en borrador" do
      order(status: "draft")

      error = assert_raises(CloseRound::PendingOrdersError) { CloseRound.run! }
      assert_match(/Hay 1 pedido en borrador y se perdería al cerrar la rueda\./, error.message)
      assert_equal 1, Order.count, "no debe borrar nada"
      assert @round.reload.active?
    end

    test "el aviso enseña los dos casos de una vez" do
      order(status: "draft")
      order(status: "captured")

      error = assert_raises(CloseRound::PendingOrdersError) { CloseRound.run! }
      assert_match(/Hay 1 pedido en borrador y 1 sin transmitir/, error.message)
      assert_match(/terminen o descarten los borradores, transmite los demás/, error.message)
    end

    test "cierra: purga los transmitidos, desactiva la rueda y limpia la selección" do
      order(status: "transmitted", erp_folio: "1A0001")

      removed = CloseRound.run!

      assert_equal 1, removed
      assert_equal 0, Order.count
      assert_not @round.reload.active?, "la rueda debe quedar inactiva"
      setting = Setting.instance
      assert_nil setting.selected_round_erp_id
      assert_nil setting.selected_round_name
    end

    test "cierra: borra el historial de corridas de sync (el panel arranca limpio)" do
      SyncRun.create!(kind: "down", started_at: 1.hour.ago)
             .finish!(status: "completed")
      SyncRun.create!(kind: "up", started_at: 30.minutes.ago)
             .finish!(status: "completed")

      CloseRound.run!

      assert_equal 0, SyncRun.count
      assert_nil SyncRun.latest("down")
      assert_nil SyncRun.latest("up")
    end

    test "no cierra si hay una corrida de sync en curso" do
      SyncRun.create!(kind: "up", started_at: Time.current)

      assert_raises(CloseRound::SyncInProgressError) { CloseRound.run! }
      assert_equal 1, SyncRun.count, "no debe borrar el run del job vivo"
      assert @round.reload.active?
    end

    test "tras cerrar, el sync-down de la siguiente rueda pasa su guarda" do
      order(status: "transmitted", erp_folio: "1A0002")
      CloseRound.run!

      assert_nothing_raised { Sync::Down.guard! }
    end

    # --- La carrera: un pedido finalizado entre la guarda y el borrado --------
    # La guarda y el borrado son dos sentencias distintas, y `capture!` no toma
    # el lock del sync. Antes, `Order.destroy_all` se llevaba esa venta sin que
    # nada avisara. Ahora solo se borran los transmitidos y se vuelve a
    # comprobar, así que la transacción entera se deshace.

    test "un pedido finalizado en plena operación deshace el cierre completo" do
      # Al pasar la guarda los dos están transmitidos, así que el cierre procede.
      order(status: "transmitted", erp_folio: "1A0003")
      rezagado = order(status: "transmitted", erp_folio: "1A0004")

      # La carrera: el capturista finaliza su pedido justo DESPUÉS de la guarda.
      # Se engancha al primer `Order.transmitted` del servicio (el conteo), que
      # ocurre entre la guarda y el borrado.
      #
      # Módulo antepuesto y no `define_singleton_method` + `remove_method`: el
      # scope del enum vive en el propio singleton de Order, así que quitarlo lo
      # borra para el resto del proceso. Este se desactiva solo tras la primera
      # llamada y queda como un `super` inocuo.
      colado = false
      Order.singleton_class.prepend(Module.new do
        define_method(:transmitted) do
          unless colado
            colado = true
            rezagado.update_columns(status: "captured", erp_folio: nil)
          end
          super()
        end
      end)

      assert_raises(CloseRound::PendingOrdersError) { CloseRound.run! }

      # Con `Order.destroy_all` y sin la segunda guarda, esa venta se perdía.
      assert_equal 2, Order.count, "no se pierde ningún pedido"
      assert @round.reload.active?, "la rueda no se cierra a medias"
      assert_equal @round.erp_round_id, Setting.instance.reload.selected_round_erp_id
    end

    test "el cierre normal solo borra los transmitidos y devuelve su cuenta" do
      2.times { |i| order(status: "transmitted", erp_folio: "1A000#{i}") }

      assert_equal 2, CloseRound.run!
      assert_equal 0, Order.count
    end
  end
end
