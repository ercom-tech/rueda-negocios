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
    orphan = SyncRun.create!(kind: "up", started_at: Time.current)

    SyncRun.recover_orphaned!

    orphan.reload
    assert orphan.failed?
    assert orphan.finished_at.present?
    assert_match(/reinició/, orphan.message)
    # El run cerrado ya no bloquea la siguiente transmisión (guard del panel).
    assert_not SyncRun.latest("up").running?
  end

  test "recover_orphaned! no toca los runs ya cerrados" do
    done = SyncRun.create!(kind: "down", started_at: Time.current)
    done.finish!(status: "completed", message: "ok")

    SyncRun.recover_orphaned!

    assert done.reload.completed?
    assert_equal "ok", done.message
  end
end
