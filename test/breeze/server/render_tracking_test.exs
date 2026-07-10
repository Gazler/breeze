defmodule Breeze.Server.RenderTrackingTest do
  use ExUnit.Case, async: true

  alias Breeze.Server.RenderTracking

  test "server-owned tables isolate renders and follow the server lifetime" do
    parent = self()

    owner =
      spawn(fn ->
        table = RenderTracking.new_table()
        send(parent, {:table_started, self(), table})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:table_started, ^owner, table}
    assert :ets.info(table, :owner) == owner

    other_tracking = RenderTracking.begin(table)
    tracking = RenderTracking.begin(table)

    RenderTracking.track_missing_live_child(other_tracking, {"other", %{}})
    RenderTracking.track_missing_live_child(tracking, {"preview", %{view: :preview}})

    assert %{missing: [{"other", %{}}]} = RenderTracking.finish(other_tracking)
    assert %{missing: [{"preview", %{view: :preview}}]} = RenderTracking.finish(tracking)

    ref = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^owner, :normal}
    assert :ets.info(table) == :undefined
  end
end
