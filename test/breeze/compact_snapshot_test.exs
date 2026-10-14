defmodule Breeze.CompactSnapshotTest do
  use ExUnit.Case, async: true

  defmodule Projected do
    @behaviour Breeze.Implicit

    def init(_, attrs, _), do: {:ok, %{payload: attrs.payload}, rerender_every: :change}
    def handle_modifiers(_, _, _), do: []
    def animate(_, box, _, _, _), do: box
    def animation_state(state, _layout), do: Map.take(state, [])
  end

  defmodule Unprojected do
    @behaviour Breeze.Implicit

    defdelegate init(children, attrs, state), to: Projected
    defdelegate handle_modifiers(type, flags, state), to: Projected
    defdelegate animate(type, box, flags, state, ctx), to: Projected
  end

  defmodule View do
    use Breeze.View

    def mount(opts, term), do: {:ok, assign(term, payload: opts[:payload])}

    def render(assigns) do
      ~H"""
      <box id="root" class="width-full height-full" payload={@payload}>
        <box id="projected" implicit={Projected} payload={@payload} screen-dim>Projected</box>
        <box id="original" implicit={Unprojected} payload={@payload}>Original</box>
      </box>
      """
    end
  end

  test "compact snapshots project compositor flags without changing layout or view state" do
    {pid, payload} = start()
    {:ok, full, _, full_decorations} = Breeze.ChildServer.render_snapshot(pid, [])

    {:ok, compact, _, compact_decorations} =
      Breeze.ChildServer.render_snapshot(pid, compact_snapshot: true)

    assert Breeze.RenderState.build_dimensions(compact) ==
             Breeze.RenderState.build_dimensions(full)

    assert Map.has_key?(full, :input_routing_signature)
    refute Map.has_key?(compact, :input_routing_signature)

    for {idx, flags} <- compact.elements do
      assert flags == Keyword.take(full.elements[idx], [:id, :__live_dimension__, :"screen-dim"])
    end

    assert Enum.any?(compact.elements, fn {_, flags} -> flags[:"screen-dim"] end)
    refute Keyword.has_key?(compact.flags, :payload)
    assert Enum.any?(full.elements, fn {_, flags} -> flags[:payload] == payload end)

    for decoration <- full_decorations, do: assert(decoration.state.payload == payload)
    states = Map.new(compact_decorations, &{&1.id, &1.state})
    assert states["projected"] == %{}
    assert states["original"] == %{payload: payload}

    term = :sys.get_state(pid)
    assert elem(term.implicit_state["projected"], 1).payload == payload
    assert term.input_routing_signature == full.input_routing_signature
  end

  test "inspector snapshots retain attributes and original animation state" do
    {pid, payload} = start()

    {:ok, inspected, _, decorations} =
      Breeze.ChildServer.render_snapshot(pid, compact_snapshot: true, render_tree?: true)

    assert Map.has_key?(inspected, :input_routing_signature)
    assert Enum.any?(inspected.elements, fn {_, flags} -> flags[:payload] == payload end)
    for decoration <- decorations, do: assert(decoration.state.payload == payload)
  end

  defp start do
    payload = Enum.map(1..1_000, &%{row: &1, cells: Enum.to_list(1..20)})
    {:ok, pid} = Breeze.ChildServer.start(view: View, start_opts: [payload: payload])
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    {pid, payload}
  end
end
