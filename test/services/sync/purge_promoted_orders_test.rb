require "test_helper"

# Purgar pedidos TRANSMITIDOS que llevan una promoción aplicada.
#
# Es el choque de dos remediaciones. La 7ª auditoría le puso a `OrderItem` un
# `before_destroy` que hace `throw :abort` cuando la partida tiene promoción
# aplicada: sin él, esconder el bote de basura en la vista no impedía que una
# pestaña rezagada borrara la partida por el endpoint. Pero ese candado es una
# regla contra el CAPTURISTA, y las dos purgas del sistema —el replace del
# sync-down y "Cerrar rueda"— pasan por el mismo `destroy`.
#
# Resultado en la laptop (2026-08-25): las partidas sobrevivían al
# `destroy_all`, sin excepción ni aviso, y el borrado del catálogo reventaba
# después con
#   PG::ForeignKeyViolation ... "promotion_tiers" ... referenced from
#   "order_items"
# El panel decía "No se pudo obtener la información. Revisa que el servidor
# esté disponible", mandando a revisar la red por un problema de datos locales.
#
# Es el flujo normal de un evento de varios días: transmitir al final del día
# y volver a obtener información al siguiente. Y al terminar, cerrar la rueda.
module Sync
  class PurgePromotedOrdersTest < ActiveSupport::TestCase
    setup do
      @user   = User.create!(erp_person_id: 9401, username: "cap_pp", password: "x", role: "capturista")
      @round  = BusinessRound.create!(erp_round_id: 9401, name: "Rueda PP", active: true)
      @client = Client.create!(erp_client_key: "PP01", name: "Cliente PP")
      Setting.instance.update!(selected_round_erp_id: @round.erp_round_id,
                               selected_round_name: @round.name)

      @product = Product.create!(erp_product_id: 9401, description: "MARTILLO PP", max_discount: 50)
      Price.create!(product: @product, credit_wholesale_price: 100, tax_rate: 16)

      @promotion = Promotion.create!(erp_promotion_id: 9401, code: "PP01", name: "PROMO PP",
                                     starts_on: 1.week.ago.to_date, ends_on: 1.week.from_now.to_date)
      @tier = @promotion.promotion_tiers.create!(erp_consecutive: 1, condition_kind: "CM",
                                                 unit: "MXN", quantity_from: 1, quantity_to: 0,
                                                 discount_percent: 10)
      @promotion.promotion_products.create!(product: @product, discount_percent: 0)
    end

    # Un pedido ya transmitido, con la promoción aplicada: sus partidas quedan
    # bloqueadas y apuntando a `promotions` y `promotion_tiers`.
    def transmitted_order_with_promotion!
      order = Order.create!(user: @user, business_round: @round, client: @client,
                            kind: "remission", local_folio: "RN-000401")
      order.order_items.create!(product: @product, position: 1, quantity: 2, unit_price: 100,
                                discount_percent: 0, tax_rate: 16, code: "9401",
                                description: "MARTILLO PP", unit: "PZA")
      Promotions::Group.new(order.reload, @promotion).apply!
      order.reload.update!(status: "transmitted", erp_folio: "1A0001",
                           transmitted_at: Time.current)
      order
    end

    test "el replace del sync-down purga un pedido transmitido con promoción" do
      transmitted_order_with_promotion!
      assert_predicate OrderItem.where.not(promotion_tier_id: nil), :any?,
                       "el pedido debe quedar apuntando al catálogo de promociones"

      # Solo la purga y el borrado del catálogo: es donde reventaba.
      down = Down.allocate
      assert_nothing_raised do
        ActiveRecord::Base.transaction do
          down.send(:purge_local_orders!)
          down.send(:clear_catalog!)
        end
      end

      assert_equal 0, Order.count, "el pedido transmitido debe quedar purgado"
      assert_equal 0, OrderItem.count
      assert_equal 0, Promotion.count, "y el catálogo debe poder borrarse"
    end

    test "cerrar rueda purga un pedido transmitido con promoción" do
      transmitted_order_with_promotion!

      assert_nothing_raised { CloseRound.run! }

      assert_equal 0, Order.count
      assert_equal 0, OrderItem.count
    end

    # La otra mitad: el candado sigue protegiendo al capturista. Que la purga
    # del sistema pase por encima NO puede abrirle la puerta a que una pestaña
    # rezagada borre una partida con promoción aplicada.
    test "el candado sigue impidiendo que se borre una partida aplicada" do
      order = Order.create!(user: @user, business_round: @round, client: @client,
                            kind: "remission", local_folio: "RN-000402")
      order.order_items.create!(product: @product, position: 1, quantity: 2, unit_price: 100,
                                discount_percent: 0, tax_rate: 16, code: "9401",
                                description: "MARTILLO PP", unit: "PZA")
      Promotions::Group.new(order.reload, @promotion).apply!

      item = order.reload.order_items.find_by(gift: false)

      assert_not item.destroy, "una partida con promoción aplicada no se borra desde la UI"
      assert OrderItem.exists?(item.id)
    end
  end
end
