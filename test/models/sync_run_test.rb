require "test_helper"

class SyncRunTest < ActiveSupport::TestCase
  test "solo puede haber UN run running por tipo (índice único parcial)" do
    SyncRun.create!(kind: "down", started_at: Time.current)

    assert_raises(ActiveRecord::RecordNotUnique) do
      SyncRun.create!(kind: "down", started_at: Time.current)
    end
  end

  test "un run cerrado ya no bloquea el siguiente del mismo tipo" do
    SyncRun.create!(kind: "down", started_at: Time.current)
           .finish!(status: "completed")

    assert SyncRun.create!(kind: "down", started_at: Time.current).persisted?
  end

  test "tipos distintos pueden correr a la vez" do
    SyncRun.create!(kind: "down", started_at: Time.current)

    assert SyncRun.create!(kind: "up", started_at: Time.current).persisted?
  end

  test "recover_orphaned! cierra como failed los runs que quedaron running" do
    # Sin pid (corrida anterior a la columna) se trata como huérfana.
    orphan = SyncRun.create!(kind: "up", started_at: Time.current)

    SyncRun.recover_orphaned!

    orphan.reload
    assert orphan.failed?
    assert orphan.finished_at.present?
    assert_match(/se quedó a medias/, orphan.message)
    # El run cerrado ya no bloquea la siguiente transmisión (guard del panel).
    assert_not SyncRun.latest("up").running?
  end

  test "recover_orphaned! respeta una corrida cuyo proceso sigue vivo" do
    # Una tarea rake corriendo en otra terminal: barrerla la marcaría
    # "interrumpida" y liberaría la pausa y las guardas encima de un sync en
    # curso. (5ª auditoría.)
    alive = SyncRun.create!(kind: "down", started_at: Time.current, pid: Process.pid)

    SyncRun.recover_orphaned!

    assert alive.reload.running?, "una corrida con proceso vivo no se barre"
  end

  # El pid reciclado tras un reinicio (a menudo por un daemon de root → EPERM
  # → "vivo") dejaba la corrida respetada indefinidamente — el único caso
  # donde reiniciar no curaba (6ª auditoría). Una corrida iniciada antes del
  # boot actual tiene al dueño muerto por definición.
  test "recover_orphaned! cierra una corrida anterior al boot aunque su pid parezca vivo" do
    orphan = SyncRun.create!(kind: "up", started_at: Time.current, pid: 1)

    # Sin minitest/mock (fuera de minitest 6): se fija el memo directamente.
    SyncRun.instance_variable_set(:@booted_at, 1.minute.from_now)
    SyncRun.recover_orphaned!
  ensure
    SyncRun.instance_variable_set(:@booted_at, nil)

    assert orphan.reload.failed?
  end

  test "recover_orphaned! cierra la corrida de un proceso muerto" do
    dead_pid = Process.spawn("true")
    Process.wait(dead_pid)
    orphan = SyncRun.create!(kind: "up", started_at: Time.current, pid: dead_pid)

    SyncRun.recover_orphaned!

    assert orphan.reload.failed?
  end

  test "start registra el pid del proceso dueño" do
    run = SyncRun.start("down")

    assert_equal Process.pid, run.pid
  end

  test "recover_orphaned! no toca los runs ya cerrados" do
    done = SyncRun.create!(kind: "down", started_at: Time.current)
    done.finish!(status: "completed", message: "ok")

    SyncRun.recover_orphaned!

    assert done.reload.completed?
    assert_equal "ok", done.message
  end
end
