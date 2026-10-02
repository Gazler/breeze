defmodule Breeze.StaticDecorationTest do
  use ExUnit.Case, async: true
  import Breeze.TestSupport.ProcessHelpers
  import Breeze.TestSupport.WaitUntil

  defmodule Overlay do
    def init(_, attrs, state),
      do: {:ok, Map.put(state, :label, attrs[:label]), rerender_every: attrs[:interval]}

    def handle_modifiers(_, _, _), do: []

    def animate(:root, box, _, state, _),
      do: {:ok, box, overlays: [%{x: 0, y: 0, content: state.label}]}

    def animate(:child, box, _, _, _), do: box
  end

  defmodule View do
    use Breeze.View

    def mount(opts, term),
      do: {:ok, assign(term, interval: Keyword.get(opts, :interval, :change), label: "CURSOR")}

    def render(assigns) do
      ~H"""
      <box id="overlay" implicit={Overlay} interval={@interval} label={@label}>shell</box>
      """
    end

    def handle_event("static", _, term),
      do: {:noreply, assign(term, interval: :change, label: "MOVED")}
  end

  defmodule StaticInputs do
    use Breeze.View
    import Breeze.Blocks
    def mount(_, term), do: {:ok, focus(term, "input")}

    def render(assigns) do
      ~H"""
      <box>
        <.input id="input" cursor-blink={false}/>
        <.textarea id="textarea" {%{"cursor-blink": false}}/>
      </box>
      """
    end
  end

  test "input components preserve explicit false options including spreads" do
    terminal = Termite.Terminal.start(adapter: Breeze.RuntimeTest.RecordingAdapter, owner: self())
    {:ok, pid} = start_app_server(view: StaticInputs, terminal: terminal)
    state = :sys.get_state(pid)
    assert length(state.frame.decorations) == 2
    assert Enum.all?(state.frame.decorations, &(&1.every_ms == :change))
    assert state.frame.animation_timer == nil
  end

  test "change overlays update on later renders without scheduling animation" do
    pid = start_view([])
    state = :sys.get_state(pid)

    assert [%{every_ms: :change, current_overlays: [%{content: "CURSOR"}]}] =
             state.frame.decorations

    assert state.frame.animation_timer == nil
    assert state.frame.next_tick_at == nil
    assert_receive {:terminal_write, output}
    assert IO.iodata_to_binary(output) =~ "CURSOR"
    switch_to_static(pid, state)
    assert :sys.get_state(pid).frame.animation_timer == nil
  end

  test "opting out cancels an existing timer and ignores its queued tick" do
    pid = start_view(interval: 60_000)
    initial = :sys.get_state(pid)
    assert is_reference(initial.frame.animation_timer)
    switch_to_static(pid, initial)
    state = :sys.get_state(pid)
    assert state.frame.animation_timer == nil
    assert Process.read_timer(initial.frame.animation_timer) == false
    send(pid, {:animation_tick, initial.frame.animation_generation})
    assert :sys.get_state(pid) == state
  end

  defp start_view(opts) do
    terminal = Termite.Terminal.start(adapter: Breeze.RuntimeTest.RecordingAdapter, owner: self())
    {:ok, pid} = start_app_server(view: View, terminal: terminal, start_opts: opts)
    pid
  end

  defp switch_to_static(pid, state) do
    Breeze.ChildServer.dispatch_event(state.view_pid, "static", %{})
    send(pid, :child_invalidated)

    assert wait_until(fn ->
             Enum.any?(:sys.get_state(pid).frame.decorations, fn decoration ->
               decoration.current_overlays == [%{x: 0, y: 0, content: "MOVED"}]
             end)
           end)
  end
end
