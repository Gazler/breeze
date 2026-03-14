defmodule Breeze.ChildServerTest do
  use ExUnit.Case, async: true

  defmodule MouseView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, clicks: [])}

    def render(assigns) do
      ~H"""
      <box><%= length(@clicks) %></box>
      """
    end

    def handle_event(_, %{"mouse" => mouse}, term) do
      {:noreply, assign(term, clicks: [mouse | term.assigns.clicks])}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule MouseTargetView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, last_target: "none")}

    def render(assigns) do
      ~H"""
      <box style="inline">
        <box id="left" focusable style="width-6 height-3 border">L</box>
        <box>
        </box>
        <box id="right" focusable style="width-6 height-3 border">R</box>
        <box>{@last_target}</box>
      </box>
      """
    end

    def handle_event(_, %{"target" => target}, term) do
      {:noreply, assign(term, last_target: target)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule MouseFocusView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, focus(term, "left")}

    def render(assigns) do
      ~H"""
      <box style="inline">
        <box id="left" focusable style="width-6 height-3 border">left</box>
        <box>
        </box>
        <box id="right" focusable style="width-6 height-3 border">right</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  test "dispatches mouse input through handle_event/3" do
    {:ok, pid} = Breeze.ChildServer.start(view: MouseView)

    assert {:noreply, nil, true} =
             Breeze.ChildServer.dispatch_input(pid, %{
               "mouse" => %{button: :left, action: :press, x: 3, y: 4, modifiers: []}
             })

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, [])
    assert box.content == "1"
  end

  test "wheel mouse events do not steal focus" do
    terminal = %Termite.Terminal{size: %{width: 20, height: 5}}
    {:ok, wheel_pid} = Breeze.ChildServer.start(view: MouseFocusView, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(wheel_pid, terminal: terminal)
    assert %{focused: "left"} = Breeze.ChildServer.metadata(wheel_pid)

    assert {:noreply, "left", false} =
             Breeze.ChildServer.dispatch_input(wheel_pid, %{
               "mouse" => %{button: :wheel_down, action: :press, x: 14, y: 2, modifiers: []}
             })

    assert %{focused: "left"} = Breeze.ChildServer.metadata(wheel_pid)
  end

  test "mouse clicks detect the clicked target id" do
    terminal = %Termite.Terminal{size: %{width: 20, height: 5}}
    {:ok, pid} = Breeze.ChildServer.start(view: MouseTargetView, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "right", true} =
             Breeze.ChildServer.dispatch_input(pid, %{
               "mouse" => %{button: :left, action: :press, x: 11, y: 2, modifiers: []}
             })

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert box.content =~ "right"
  end
end
