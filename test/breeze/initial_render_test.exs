defmodule Breeze.InitialRenderTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [start_child_server: 1]

  defmodule EmptyView do
    use Breeze.View

    def render(assigns) do
      send(assigns.owner, :view_rendered)

      ~H"""
      <box>Count: {@count}</box>
      """
    end
  end

  test "the initial render prepass only runs once when implicit state remains empty" do
    {:ok, pid} =
      start_child_server(view: EmptyView, assigns: %{count: 0, owner: self()})

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, [])
    initial_render_count = drain_view_renders()
    assert initial_render_count > 1

    assert :ok = Breeze.ChildServer.update_assigns(pid, %{count: 1, owner: self()})
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, [])
    assert drain_view_renders() == initial_render_count - 1
  end

  defp drain_view_renders(count \\ 0) do
    receive do
      :view_rendered -> drain_view_renders(count + 1)
    after
      0 -> count
    end
  end
end
