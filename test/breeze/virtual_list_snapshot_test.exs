defmodule Breeze.VirtualListSnapshotTest do
  use ExUnit.Case, async: true

  defmodule GridList do
    use Breeze.View
    import Breeze.Blocks

    def mount(opts, term) do
      {:ok,
       term |> assign(items: Enum.to_list(1..Keyword.fetch!(opts, :count))) |> focus("items")}
    end

    def render(assigns) do
      ~H"""
      <box class="grid grid-cols-1 grid-rows-1 w-screen h-screen">
        <.list id="items" virtual loop={false} class="w-full h-full">
          <:item :for={index <- @items} value={to_string(index)}>Item {index}</:item>
        </.list>
      </box>
      """
    end
  end

  test "full grid snapshots omit lazy render closures before copying between processes" do
    # Keep this small: the old reply copied each slot's shared context repeatedly.
    session = Breeze.Test.start!(GridList, start_opts: [count: 100], size: {80, 20})
    on_exit(fn -> Breeze.Test.stop(session) end)

    {:ok, acc, box, _} =
      Breeze.ChildServer.render_snapshot(session.pid, terminal: session.terminal)

    assert box.content =~ "Item 1"
    # BackBreeze may flatten grid children; the snapshot must still contain no closures.
    refute contains_function?({acc, box})
    bytes = :erts_debug.flat_size({acc, box}) * :erlang.system_info(:wordsize)
    assert bytes < 200_000
    assert {:ok, _, rendered} = Breeze.ChildServer.render(session.pid, terminal: session.terminal)
    refute contains_function?(rendered)
    assert :erts_debug.flat_size(rendered) * :erlang.system_info(:wordsize) < 200_000
  end

  test "20k plain-text virtual rows support full snapshots, End, Home and resize" do
    session = Breeze.Test.start!(GridList, start_opts: [count: 20_000], size: {80, 20})
    on_exit(fn -> Breeze.Test.stop(session) end)
    assert Breeze.Test.render_text!(session) =~ "Item 1"
    assert Breeze.Test.element!(session, "items").content_height == 20_000
    Breeze.Test.input(session, "End")
    assert Breeze.Test.render_text!(session) =~ "Item 20000"
    session = Breeze.Test.resize(session, {80, 50})
    output = Breeze.Test.render_text!(session)
    visible = Breeze.Test.element!(session, "items").viewport_height
    assert output =~ "Item #{20_000 - visible + 1}"
    assert output =~ "Item 20000"

    {:ok, acc, box, _} =
      Breeze.ChildServer.render_snapshot(session.pid, terminal: session.terminal)

    assert :erts_debug.flat_size({acc, box}) * :erlang.system_info(:wordsize) < 10_000_000
    Breeze.Test.input(session, "Home")
    assert Breeze.Test.render_text!(session) =~ "Item 1"
  end

  defp contains_function?(term) when is_function(term), do: true

  defp contains_function?(term) when is_map(term),
    do: term |> :maps.to_list() |> Enum.any?(&contains_function?/1)

  defp contains_function?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&contains_function?/1)

  defp contains_function?(term) when is_list(term), do: Enum.any?(term, &contains_function?/1)
  defp contains_function?(_term), do: false
end
