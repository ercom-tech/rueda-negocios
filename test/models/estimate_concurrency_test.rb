require "test_helper"

# Dos conexiones de verdad, sin la transacción de la prueba: los candados de
# fila solo se pueden comprobar así (15ª auditoría, huecos de cobertura). Cada
# caso fuerza el orden con una cola —uno toma el candado y lo sostiene, el otro
# llega después—, así que no depende de la suerte del planificador: sin el
# candado, el resultado malo sale siempre.
#
# Como lo que escribe se CONFIRMA, la prueba se cuida de no ensuciar la base
# de pruebas (16ª auditoría): una corrida interrumpida dejaba una rueda ACTIVA,
# y toda corrida siguiente de la suite daba 68 fallas hasta limpiarla a mano.
# Por eso la rueda nace inactiva (nada más depende de ella), el arranque barre
# lo que haya dejado una corrida anterior, y la espera tiene tope.
class EstimateConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  ERP_ID = 970_801
  WAIT = 5 # segundos: el candado se sostiene 0.4

  setup do
    sweep
    @user  = User.create!(erp_person_id: ERP_ID, username: "cap_conc", password: "x", role: "capturista")
    @round = BusinessRound.create!(erp_round_id: ERP_ID, name: "Rueda conc", active: false)
    @counter_before = Setting.instance.last_estimate_number
  end

  teardown do
    sweep
    Setting.instance.update_columns(last_estimate_number: @counter_before) if @counter_before
  end

  def sweep
    users  = User.where(erp_person_id: ERP_ID)
    orders = Order.where(user_id: users.select(:id))
    OrderItem.where(order_id: orders.select(:id)).delete_all
    orders.delete_all
    BusinessRound.where(erp_round_id: ERP_ID).delete_all
    users.delete_all
  end

  # Sostiene una transacción abierta (con lo que `hold` haya tomado) hasta que
  # el otro hilo ya esté esperando. Si `hold` falla, el error sube aquí en vez
  # de dejar al hilo principal esperando para siempre una señal que no llega.
  def holding(hold)
    taken = Queue.new
    thread = Thread.new do
      Thread.current.report_on_exception = false # el error se reporta aquí abajo
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          result = hold.call
          taken << :ok
          sleep 0.4
          result
        end
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      taken << e
      raise
    end
    signal = taken.pop(timeout: WAIT)
    raise signal if signal.is_a?(Exception)
    raise "el hilo que sostiene el candado no avisó en #{WAIT} s" if signal.nil?

    [ thread, yield ]
  end

  def value_of(thread)
    thread.join(WAIT) or raise "un hilo no terminó en #{WAIT} s"
    thread.value
  end

  test "dos guardados a la vez no sacan el mismo número de cotización" do
    first, second = holding(-> { Setting.next_estimate_number! }) do
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { Setting.next_estimate_number! } }
    end

    assert_not_equal value_of(first), value_of(second)
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

    value_of(inserting)
    assert_equal 1, value_of(purging)
    assert_not Order.exists?(estimate.id)
    assert_equal 0, OrderItem.where(order_id: estimate.id).count
  end

  # La prueba misma: si lo que sostiene el candado falla, termina con el error
  # en vez de colgarse (pasaba con `taken.pop` sin tope, 16ª auditoría).
  test "si el hilo que sostiene el candado falla, la prueba termina con su error" do
    error = assert_raises(RuntimeError) do
      holding(-> { raise "falla a propósito" }) { :nunca }
    end

    assert_equal "falla a propósito", error.message
  end
end
