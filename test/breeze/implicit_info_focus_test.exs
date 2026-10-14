defmodule Breeze.ImplicitInfoFocusTest do
  use ExUnit.Case, async: true

  defmodule Implicit do
    @behaviour Breeze.Implicit

    def init(_, attrs, state),
      do: {:ok, Map.put_new(state, :owner, attrs.owner)}

    def handle_modifiers(_, _, _), do: []
    def handle_event(_, _, state), do: {:noreply, state, capture_mouse: true}

    def blur(state) do
      send(state.owner, :blurred)
      Map.put(state, :blurred?, true)
    end
  end

  defmodule View do
    use Breeze.View

    def mount(opts, term), do: {:ok, term |> assign(owner: opts[:owner]) |> focus("input")}

    def render(assigns) do
      ~H"""
      <box id="input" implicit={Implicit} focusable owner={@owner} class="width-10 height-2">Input</box>
      """
    end

    def handle_info(:unfocus, term), do: {:noreply, focus(term, nil)}

    def handle_info(:unfocus_without_render, term),
      do: {:noreply, focus(term, nil), invalidate: false}
  end

  test "asynchronous view focus changes blur the implicit and release capture" do
    for message <- [:unfocus, :unfocus_without_render] do
      {:ok, pid} = Breeze.ChildServer.start(view: View, start_opts: [owner: self()])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      Breeze.ChildServer.render_snapshot(pid, focused: "input")
      Breeze.ChildServer.dispatch_input(pid, "x")
      assert :sys.get_state(pid).mouse_capture == "input"

      send(pid, message)
      state = :sys.get_state(pid)
      assert_receive :blurred
      assert state.focused == nil
      assert state.mouse_capture == nil
      assert elem(state.implicit_state["input"], 1).blurred?
    end
  end
end
