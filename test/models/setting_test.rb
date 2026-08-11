require "test_helper"

class SettingTest < ActiveSupport::TestCase
  # `settings` no tiene fixture, así que nada la trunca entre corridas: una fila
  # dejada por un `bin/rails runner` con RAILS_ENV=test tumbaba dos de estas
  # pruebas con un error que no apunta a su causa.
  setup { Setting.delete_all }

  test "instance crea la fila única al primer acceso y la reusa después" do
    assert_equal 0, Setting.count
    s = Setting.instance
    assert_equal 1, Setting.count
    assert_equal s, Setting.instance
  end

  test "la BD impide una segunda fila (índice singleton)" do
    Setting.instance

    assert_raises(ActiveRecord::RecordNotUnique) { Setting.create! }
  end

  test "instance sobrevive la carrera de creación (RecordNotUnique → relee)" do
    ganadora = Setting.create!
    # Simula al perdedor de la carrera: primero no ve la fila (create! choca
    # con el índice singleton) y en el rescue la relee.
    respuestas = [ nil, ganadora ]
    Setting.define_singleton_method(:first) { respuestas.shift }

    assert_equal ganadora, Setting.instance
  ensure
    Setting.singleton_class.remove_method(:first)
  end
end
