require "test_helper"

# Dos conexiones de verdad, sin la transacción de la prueba: los candados de
# fila solo se pueden comprobar así (15ª auditoría, huecos de cobertura). Cada
# caso fuerza el orden con una cola —uno toma el candado y lo sostiene, el otro
# llega después—, así que no depende de la suerte del planificador: sin el
# candado, el resultado malo sale siempre.
class EstimateConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user  = User.create!(erp_person_id: 970_801, username: "cap_conc", password: "x", role: "capturista")
    @round = BusinessRound.create!(erp_round_id: 970_801, name: "Rueda conc", active: true)
    @counter_before = Setting.instance.last_estimate_number
  end

  teardown do
    orders = Order.where(user: @user)
    OrderItem.where(order_id: orders.select(:id)).delete_all
    orders.delete_all
    @round.destroy!
    @user.destroy!
    Setting.instance.update_columns(last_estimate_number: @counter_before)
  end

  # Sostiene una transacción abierta (con lo que `hold` haya tomado) hasta que
  # el otro hilo ya esté esperando.
  def holding(hold)
    taken = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          result = hold.call
          taken << :ok
          sleep 0.4
          result
        end
      end
    end
    taken.pop
    [ thread, yield ]
  end

  test "dos guardados a la vez no sacan el mismo número de cotización" do
    first, second = holding(-> { Setting.next_estimate_number! }) do
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { Setting.next_estimate_number! } }
    end

    assert_not_equal first.value, second.value
  end

  # La partida que se inserta mientras "Cerrar rueda" borra las cotizaciones:
  # sin el candado de `purge_estimates!`, el borrado de la cotización chocaba
  # con la partida nueva y la operación entera fallaba por la llave foránea.
  test "una partida que entra mientras se purgan las cotizaciones se borra con ellas" do
    estimate = Order.create!(user: @user, business_round: @round, document: "estimate")
    insert = lambda do
      estimate.order_items.create!(position: 1, quantity: 1, unit_price: 10, tax_rate: 0, discount_percent: 0)
    end

    inserting, purging = holding(insert) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActiveRecord::Base.transaction { Order.purge_estimates! }
        end
      end
    end

    inserting.join
    assert_equal 1, purging.value
    assert_not Order.exists?(estimate.id)
    assert_equal 0, OrderItem.where(order_id: estimate.id).count
  end
end
