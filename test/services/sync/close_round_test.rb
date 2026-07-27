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
      assert_match(/1 pedido/, error.message)
      assert_equal 1, Order.count, "no debe borrar nada"
      assert @round.reload.active?
    end

    test "cierra: purga borradores y transmitidos, desactiva la rueda y limpia la selección" do
      order(status: "draft")
      order(status: "transmitted", erp_folio: "1A0001")

      removed = CloseRound.run!

      assert_equal 2, removed
      assert_equal 0, Order.count
      assert_not @round.reload.active?, "la rueda debe quedar inactiva"
      setting = Setting.instance
      assert_nil setting.selected_round_erp_id
      assert_nil setting.selected_round_name
    end

    test "tras cerrar, el sync-down de la siguiente rueda pasa su guarda" do
      order(status: "transmitted", erp_folio: "1A0002")
      CloseRound.run!

      assert_nothing_raised { Sync::Down.new({}).send(:guard!) }
    end
  end
end
