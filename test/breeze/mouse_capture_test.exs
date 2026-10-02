defmodule Breeze.MouseCaptureTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [start_child_server: 1]

  alias Breeze.ChildServer

  defmodule Draggable do
    @behaviour Breeze.Implicit

    def init(_, _, state),
      do: {:ok, state |> Map.put_new(:dragging?, false) |> Map.put_new(:events, [])}

    def handle_modifiers(_, _, _), do: []

    def handle_event(_, %{"mouse" => mouse} = event, state) do
      state = %{state | events: [event | state.events]}

      case mouse do
        %{"button" => "left", "action" => "press"} ->
          {:noreply, %{state | dragging?: true}, capture_mouse: true}

        %{"button" => "left", "action" => "release"} ->
          {:noreply, %{state | dragging?: false}, capture_mouse: false}

        _ ->
          {:noreply, state}
      end
    end

    def handle_event(_, %{"key" => "Escape"}, state),
      do: {:noreply, %{state | dragging?: false}, capture_mouse: false}

    def handle_event(_, _, state), do: {:noreply, state}
  end

  defmodule Receiver do
    @behaviour Breeze.Implicit

    def init(_, _, state), do: {:ok, Map.put_new(state, :events, [])}
    def handle_modifiers(_, _, _), do: []

    def handle_event(_, %{"mouse" => _} = event, state),
      do: {:noreply, %{state | events: [event | state.events]}}

    def handle_event(_, _, state), do: {:noreply, state}
  end

  defmodule View do
    use Breeze.View

    def mount(_, term), do: {:ok, term |> assign(events: [], show_drag: true) |> focus("drag")}

    def render(assigns) do
      ~H"""
      <box class="pl-4 pt-2">
        <box :if={@show_drag} id="drag" implicit={Draggable} focusable class="border w-10 h-4">
          Drag
        </box>
        <box id="other" implicit={Receiver} focusable class="w-10 h-3">Other</box>
      </box>
      """
    end

    def handle_event(:input, event, term),
      do: {:noreply, assign(term, events: [event | term.assigns.events])}

    def handle_info({:focus, id}, term), do: {:noreply, focus(term, id)}
  end

  setup do
    terminal = %Termite.Terminal{size: %{width: 40, height: 20}}
    {:ok, pid} = start_child_server(view: View, terminal: terminal)
    {:ok, _, _} = ChildServer.render(pid, terminal: terminal)
    %{mouse_targets: %{"drag" => drag, "other" => other}} = ChildServer.layout_snapshot(pid)

    %{pid: pid, terminal: terminal, drag: drag, other: other}
  end

  test "dragging captures movement and release over another target until released", ctx do
    %{pid: pid, drag: drag, other: other} = ctx
    assert {:noreply, "drag", true} = mouse(pid, "press", drag.left + 1, drag.top + 1)
    assert implicit_state(pid, "drag").dragging?

    x = other.left + 2
    y = other.top + 1
    assert y > drag.bottom
    assert {:noreply, "drag", true} = mouse(pid, "move", x, y)

    assert [move, press] = implicit_state(pid, "drag").events
    assert press["row"] == 0
    assert press["col"] == 0
    assert move["target"] == "drag"
    assert move["focused"] == "drag"
    assert move["row"] == y - drag.top - 1
    assert move["col"] == x - drag.left - 1
    assert move["mouse"] == %{"button" => "left", "action" => "move", "x" => x, "y" => y}
    assert implicit_state(pid, "other").events == []

    assert {:noreply, "drag", true} = mouse(pid, "release", x, y)
    assert %{dragging?: false, events: [release, ^move, ^press]} = implicit_state(pid, "drag")
    assert release["target"] == "drag"
    assert release["mouse"]["action"] == "release"
    assert implicit_state(pid, "other").events == []

    assert {:noreply, "other", true} = mouse(pid, "press", x, y)
    assert [event] = implicit_state(pid, "other").events
    assert event["target"] == "other"
    assert length(implicit_state(pid, "drag").events) == 3
  end

  test "capture routes events outside every target and preserves screen coordinates", ctx do
    %{pid: pid, drag: drag} = ctx
    assert drag.left > 0 and drag.top > 0
    mouse(pid, "press", drag.left + 1, drag.top + 1)

    assert {:noreply, "drag", true} = mouse(pid, "move", 0, 0)
    assert [move, _] = implicit_state(pid, "drag").events
    assert move["target"] == "drag"
    assert move["row"] == 0
    assert move["col"] == 0
    assert move["mouse"]["x"] == 0
    assert move["mouse"]["y"] == 0
    assert ChildServer.metadata(pid).assigns.events == []

    assert {:noreply, "drag", true} = mouse(pid, "release", 39, 19)
    assert %{dragging?: false, events: [release | _]} = implicit_state(pid, "drag")
    assert release["target"] == "drag"
    assert release["row"] == 19 - drag.top - 1
    assert release["col"] == 39 - drag.left - 1

    mouse(pid, "move", 39, 19)

    assert [%{"mouse" => %{"action" => "move", "x" => 39, "y" => 19}}] =
             ChildServer.metadata(pid).assigns.events
  end

  test "without a capture request, hit testing and view fallback remain intact", ctx do
    %{pid: pid, other: other} = ctx
    refute implicit_state(pid, "drag").dragging?

    assert {:noreply, "drag", true} = mouse(pid, "move", other.left, other.top)
    assert [%{"target" => "other"}] = implicit_state(pid, "other").events
    assert implicit_state(pid, "drag").events == []

    mouse(pid, "move", 39, 19)
    assert [%{"mouse" => %{"x" => 39, "y" => 19}}] = ChildServer.metadata(pid).assigns.events
    assert implicit_state(pid, "drag").events == []
  end

  test "cancelling a drag releases capture before the next render", ctx do
    %{pid: pid, drag: drag, other: other} = ctx
    mouse(pid, "press", drag.left + 1, drag.top + 1)
    assert {:noreply, "drag", true} = ChildServer.dispatch_input(pid, "Escape")
    refute implicit_state(pid, "drag").dragging?

    mouse(pid, "move", other.left, other.top)
    assert [%{"target" => "other"}] = implicit_state(pid, "other").events
    assert [%{"mouse" => %{"action" => "press"}}] = implicit_state(pid, "drag").events
  end

  test "losing and regaining focus does not resume capture", ctx do
    %{pid: pid, drag: drag, other: other} = ctx
    mouse(pid, "press", drag.left + 1, drag.top + 1)
    assert {:noreply, "other", true} = ChildServer.dispatch_input(pid, "\t")
    assert implicit_state(pid, "drag").dragging?

    mouse(pid, "move", other.left, other.top)
    assert [%{"target" => "other"}] = implicit_state(pid, "other").events
    assert length(implicit_state(pid, "drag").events) == 1

    mouse(pid, "move", 39, 19)
    assert [%{"mouse" => %{"x" => 39, "y" => 19}}] = ChildServer.metadata(pid).assigns.events

    assert {:noreply, "drag", true} = ChildServer.set_focus(pid, "drag")
    mouse(pid, "move", other.left, other.top)
    assert length(implicit_state(pid, "other").events) == 2
    assert length(implicit_state(pid, "drag").events) == 1
  end

  test "focused implicits that do not request capture retain normal mouse routing", ctx do
    %{pid: pid, drag: drag, other: other} = ctx
    assert {:noreply, "other", true} = mouse(pid, "press", other.left, other.top)
    assert {:noreply, "other", true} = mouse(pid, "move", drag.left + 1, drag.top + 1)
    assert [%{"target" => "drag"}] = implicit_state(pid, "drag").events
    refute implicit_state(pid, "drag").dragging?
    assert length(implicit_state(pid, "other").events) == 1
  end

  test "capture survives rerendering without another request", ctx do
    %{pid: pid, terminal: terminal, drag: drag, other: other} = ctx
    mouse(pid, "press", drag.left + 1, drag.top + 1)
    assert {:ok, _, _} = ChildServer.render(pid, terminal: terminal)

    mouse(pid, "move", other.left, other.top)

    assert [%{"target" => "drag", "mouse" => %{"action" => "move"}}, _] =
             implicit_state(pid, "drag").events

    assert implicit_state(pid, "other").events == []
  end

  test "removing and restoring the capturing element does not resume capture", ctx do
    %{pid: pid, terminal: terminal, drag: drag} = ctx
    mouse(pid, "press", drag.left + 1, drag.top + 1)
    :ok = ChildServer.update_assigns(pid, show_drag: false)
    assert {:ok, _, _} = ChildServer.render(pid, terminal: terminal, focused: "drag")
    refute Map.has_key?(ChildServer.layout_snapshot(pid).mouse_targets, "drag")

    :ok = ChildServer.update_assigns(pid, show_drag: true)
    assert {:ok, _, _} = ChildServer.render(pid, terminal: terminal, focused: "drag")
    assert implicit_state(pid, "drag").dragging?

    other = ChildServer.layout_snapshot(pid).mouse_targets["other"]
    mouse(pid, "move", other.left, other.top)
    assert [%{"target" => "other"}] = implicit_state(pid, "other").events
    assert length(implicit_state(pid, "drag").events) == 1
  end

  test "focus changes from view messages clear capture immediately", ctx do
    %{pid: pid, drag: drag, other: other} = ctx
    mouse(pid, "press", drag.left + 1, drag.top + 1)
    send(pid, {:focus, "other"})
    assert ChildServer.metadata(pid).focused == "other"
    send(pid, {:focus, "drag"})
    assert ChildServer.metadata(pid).focused == "drag"

    mouse(pid, "move", other.left, other.top)
    assert [%{"target" => "other"}] = implicit_state(pid, "other").events
    assert length(implicit_state(pid, "drag").events) == 1
  end

  defp mouse(pid, action, x, y) do
    ChildServer.dispatch_input(pid, %{
      "mouse" => %{"button" => "left", "action" => action, "x" => x, "y" => y}
    })
  end

  defp implicit_state(pid, id) do
    {_module, state} = ChildServer.metadata(pid).implicit_state[id]
    state
  end
end
