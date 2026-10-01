defmodule Breeze.VirtualListResizeTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers

  defmodule View do
    use Breeze.View
    import Breeze.Blocks

    def mount(_, term), do: {:ok, term |> focus("items") |> assign(items: 0..249)}

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <.list id="items" virtual list-selected="207" class="width-34 height-full">
          <:item :for={n <- @items} value={to_string(n)}>
            <box class="width-full">default/list-perf-{n} stopped</box>
          </:item>
        </.list>
      </box>
      """
    end
  end

  defmodule Adapter do
    @behaviour Termite.Terminal.Adapter
    def start(opts), do: {:ok, %{size: Keyword.fetch!(opts, :size), reader: make_ref()}}
    def reader(state), do: {:ok, state.reader}
    def write(state, _data), do: {:ok, state}
    def resize(state), do: Agent.get(state.size, & &1)
  end

  test "growing a structured virtual list fills the viewport on the first resized frame" do
    terminal = %Termite.Terminal{size: %{width: 100, height: 50}}
    {:ok, pid} = start_child_server(view: View, terminal: terminal)
    {:ok, _, initial} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert item_count(initial) == 48

    terminal = %{terminal | size: %{width: 100, height: 75}}
    {:ok, _, resized} = Breeze.ChildServer.render(pid, terminal: terminal)
    {:ok, _, _} = Breeze.ChildServer.render(pid, terminal: terminal)
    {:ok, _, settled} = Breeze.ChildServer.render(pid, terminal: terminal)

    # The same state and terminal size should not need further renders to
    # fill the newly exposed rows. Clamp the offset to fill all 73 visible rows.
    assert item_count(settled) == 73
    assert item_count(resized) == item_count(settled)
    assert resized.content == settled.content
  end

  test "repeated shrinking and growing settles each frame without further input" do
    terminal = %Termite.Terminal{size: %{width: 100, height: 50}}
    {:ok, pid} = start_child_server(view: View, terminal: terminal)

    for height <- [50, 75, 40, 75, 30, 60] do
      terminal = %{terminal | size: %{width: 100, height: height}}
      {:ok, _, resized} = Breeze.ChildServer.render(pid, terminal: terminal)
      {:ok, _, settled} = Breeze.ChildServer.render(pid, terminal: terminal)
      assert resized.content == settled.content

      {_, state} = Breeze.ChildServer.metadata(pid).implicit_state["items"]
      assert state.viewport_height == height - 2
      assert item_count(resized) == min(height - 2, 250 - state.offset)
    end
  end

  test "runtime resize renders the expanded window immediately" do
    {:ok, size} = start_supervised({Agent, fn -> %{width: 100, height: 50} end})
    terminal = Termite.Terminal.start(adapter: Adapter, size: size)
    {:ok, runtime} = start_app_server(view: View, terminal: terminal)
    initial = :sys.get_state(runtime)
    assert item_count(%{content: initial.frame.base_output}) == 48

    Agent.update(size, fn _ -> %{width: 100, height: 75} end)
    send(runtime, {terminal.reader, {:signal, :winch}})
    resized = :sys.get_state(runtime)

    assert item_count(%{content: resized.frame.base_output}) == 73
    assert resized.crash == nil
  end

  defp item_count(box) do
    box.content
    |> BackBreeze.Utils.strip_escape_chars()
    |> then(&Regex.scan(~r/default\/list-perf-/, &1))
    |> length()
  end
end
