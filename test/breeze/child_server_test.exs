defmodule Breeze.ChildServerTest do
  use ExUnit.Case, async: true

  alias Breeze.Theme

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

  defmodule KeybindingView do
    use Breeze.View

    def mount(_opts, term) do
      {:ok,
       term
       |> focus("save")
       |> put_local_keybindings([{"q", "Quit"}])
       |> put_focus_keybindings("save", [
         {"Enter", "Save", fn _event, term -> {:noreply, assign(term, saved?: true)} end}
       ])
       |> assign(saved?: false)}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box id="save" focusable>saved: {@saved?}</box>
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

  test "metadata exposes active keybindings and local handlers dispatch before handle_event/3" do
    {:ok, pid} = Breeze.ChildServer.start(view: KeybindingView)

    assert %{active_keybindings: [%{key: "q", label: "Quit"}, %{key: "Enter", label: "Save"}]} =
             Breeze.ChildServer.metadata(pid)

    assert {:noreply, "save", true} = Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, [])
    assert box.content =~ "saved: true"
  end

  test "palette notifications refresh system themes loaded from a theme struct source" do
    ref = make_ref()

    terminal = %Termite.Terminal{
      reader: ref,
      size: %{width: 80, height: 24}
    }

    theme_source = Theme.system()

    {:ok, pid} =
      Breeze.ChildServer.start(
        view: MouseView,
        terminal: terminal,
        theme: theme_source,
        theme_source: theme_source
      )

    assert %{theme: %{mode: :system16}} = Breeze.ChildServer.metadata(pid)

    send(pid, {:breeze_theme_palette, {:reader, make_ref()}, :ready})
    assert %{theme: %{mode: :system16}} = Breeze.ChildServer.metadata(pid)

    assert :ready =
             Theme.finish_runtime_palette_probe(terminal, %{
               1 => {170, 34, 51},
               2 => {34, 170, 51},
               3 => {204, 187, 51},
               4 => {51, 85, 170},
               5 => {153, 51, 170},
               6 => {51, 170, 170},
               7 => {221, 221, 221},
               8 => {119, 119, 119},
               9 => {221, 102, 68},
               10 => {68, 204, 85},
               11 => {230, 209, 90},
               12 => {95, 123, 224},
               13 => {179, 107, 212},
               14 => {90, 214, 214},
               background: {16, 17, 18},
               foreground: {240, 240, 240}
             })

    send(pid, {:breeze_theme_palette, {:reader, ref}, :ready})

    assert %{theme: %{mode: :system}} = Breeze.ChildServer.metadata(pid)
  end
end
