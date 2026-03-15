defmodule Breeze.LiveViewTest do
  use ExUnit.Case, async: true

  alias Breeze.ChildServer
  alias Breeze.Renderer
  alias Breeze.Template

  defmodule CounterChild do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(count: 1) |> focus("button")}
    end

    def render(assigns) do
      ~H"""
      <box id="panel" style="border">
        <box id="button" focusable>Count: {@count}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule ParentLiveExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={CounterChild} start_opts={@start_opts}>
        </live>
      </box>
      """
    end
  end

  defmodule AnimatedChild do
    use Breeze.View

    def mount(_opts, term) do
      send(self(), :tick)
      {:ok, assign(term, frame: 0)}
    end

    def render(assigns) do
      ~H"""
      <box id="panel">Frame: {@frame}</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}

    def handle_info(:tick, term) do
      {:noreply, assign(term, frame: term.assigns.frame + 1)}
    end

    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule FocusedChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="button" focusable style="focus:inverse">Focusable</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule SpinnerChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="spinner" implicit={Breeze.Implicit.AsyncSpinner} style="width-1">
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "render_to_tree preserves typed live attrs" do
    [{:box, _, [{:live, attrs}]}] =
      ParentLiveExample.render(%{start_opts: [seed: 1]})
      |> Template.render_to_tree(%{start_opts: [seed: 1]})

    assert attrs.id == "child"
    assert attrs.view == CounterChild
    assert attrs.start_opts == [seed: 1]
  end

  test "child server keeps its own state across events" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

    assert %{focused: "button", view: CounterChild} = ChildServer.metadata(pid)

    assert {:noreply, "button", true} =
             ChildServer.dispatch_event(pid, :ignore_me, %{"key" => "+"})

    {:ok, _acc, box} = ChildServer.render(pid, focused: "button", implicit_state: %{})
    assert box.content =~ "Count: 2"
  end

  test "child server dispatch_input advances focus and can clear it" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

    assert {:noreply, nil, true} = ChildServer.dispatch_input(pid, "\t")
    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})
    refute box.content =~ "\e[7m"
  end

  test "child server reports unhandled keys as unconsumed" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

    assert {:noreply, "button", false} = ChildServer.dispatch_input(pid, "x")
    assert {:noreply, "button", true} = ChildServer.dispatch_input(pid, "+")
  end

  test "child server render_snapshot exposes animate-capable implicit boxes" do
    {:ok, pid} = ChildServer.start(view: SpinnerChild, start_opts: [])

    assert {:ok, _acc, _box, [%{box: %BackBreeze.Box{}, every_ms: 120, id: "spinner"}]} =
             ChildServer.render_snapshot(pid, focused: nil, implicit_state: %{})
  end

  test "renderer namespaces child ids and focusables" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

    {acc, box} =
      Renderer.render(ParentLiveExample, %{start_opts: []},
        live_view: fn %{id: "child"}, _opts ->
          {:ok, child_acc, child_box} =
            ChildServer.render(pid, focused: "button", implicit_state: %{})

          {:rendered, "child", child_acc, child_box}
        end
      )

    assert acc.ids == ["child::panel", "child::button"]
    assert acc.focusables == ["child::button"]
    assert box.content =~ "Count: 1"
  end

  defmodule DualLiveExample do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box>
        <live id="left" view={CounterChild} start_opts={[]}>
        </live>
        <live id="right" view={CounterChild} start_opts={[]}>
        </live>
      </box>
      """
    end
  end

  test "root child tab traverses namespaced live child focusables" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, left_pid} = ChildServer.start(view: CounterChild, start_opts: [], terminal: terminal)
    {:ok, right_pid} = ChildServer.start(view: CounterChild, start_opts: [], terminal: terminal)
    {:ok, root_pid} = ChildServer.start(view: DualLiveExample, start_opts: [], terminal: terminal)

    live_view = fn
      %{id: "left"}, _opts ->
        {:ok, child_acc, child_box, _decorations} =
          ChildServer.render_snapshot(left_pid,
            focused: "button",
            implicit_state: %{},
            terminal: terminal
          )

        {:rendered, "left", child_acc, child_box}

      %{id: "right"}, _opts ->
        {:ok, child_acc, child_box, _decorations} =
          ChildServer.render_snapshot(right_pid,
            focused: "button",
            implicit_state: %{},
            terminal: terminal
          )

        {:rendered, "right", child_acc, child_box}
    end

    assert {:ok, _acc, _box, _decorations} =
             ChildServer.render_snapshot(root_pid, terminal: terminal, live_view: live_view)

    assert %{focused: "left::button"} = ChildServer.metadata(root_pid)
    assert {:noreply, "right::button", true} = ChildServer.dispatch_input(root_pid, "\t")
    assert {:noreply, nil, true} = ChildServer.dispatch_input(root_pid, "\t")

    assert {:ok, _acc, _box, _decorations} =
             ChildServer.render_snapshot(root_pid, terminal: terminal, live_view: live_view)

    assert %{focused: nil} = ChildServer.metadata(root_pid)
  end

  test "unfocused live children do not render their own local focus ring" do
    {:ok, pid} = ChildServer.start(view: FocusedChild, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})

    refute box.content =~ "\e[7m"
  end

  test "child server emits invalidation on async state changes" do
    parent = self()

    {:ok, pid} =
      ChildServer.start(
        view: AnimatedChild,
        start_opts: [],
        invalidate: fn -> send(parent, :invalidate) end
      )

    assert_receive :invalidate

    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})
    assert box.content =~ "Frame: 1"
  end

  test "global keybindings are dispatched before focused event handling" do
    event = %{"key" => "q"}

    term = %Breeze.Term{
      view: CounterChild,
      global_keybindings: [
        {"q", fn _event, term -> {:noreply, Breeze.View.assign(term, handled?: true)} end}
      ],
      assigns: %{}
    }

    assert {:noreply, %Breeze.Term{assigns: %{handled?: true}}} =
             Breeze.GlobalKeybindings.dispatch(event, term)
  end
end
