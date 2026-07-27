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
end
