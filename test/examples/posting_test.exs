defmodule PostingTest do
  use ExUnit.Case, async: false

  setup_all do
    Application.put_env(:breeze, :example_mode, :load_only)
    Code.require_file("examples/posting.exs")

    on_exit(fn ->
      Application.delete_env(:breeze, :example_mode)
    end)

    :ok
  end

  test "F1 opens help modal and focuses it, Escape closes and restores url focus" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(box.content) =~ "https://jsonplaceholder.typicode.com/posts"
    assert %{focused: "url"} = Breeze.ChildServer.metadata(pid)

    assert {:noreply, "help", true} = Breeze.ChildServer.dispatch_input(pid, "F1")

    assert {:ok, _acc, help_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(help_box.content) =~ "Keyboard Shortcuts"
    assert visible(help_box.content) =~ "Close this dialog"
    assert %{focused: "help"} = Breeze.ChildServer.metadata(pid)

    assert {:noreply, "url", true} = Breeze.ChildServer.dispatch_input(pid, "Escape")

    assert {:ok, _acc, closed_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    refute visible(closed_box.content) =~ "Keyboard Shortcuts"
    assert %{focused: "url"} = Breeze.ChildServer.metadata(pid)
  end

  test "Ctrl-T opens the method dropdown" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "method", true} = Breeze.ChildServer.dispatch_input(pid, "\x14")

    assert {:ok, _acc, open_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(open_box.content) =~ "GET"
    assert visible(open_box.content) =~ "DELETE"
    assert %{focused: "method"} = Breeze.ChildServer.metadata(pid)
  end

  test "headers form adds a request header" do
    terminal = %Termite.Terminal{size: %{width: 120, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(box.content) =~ "╱╱╱"

    assert {:noreply, "request-header-name", true} =
             Breeze.ChildServer.set_focus(pid, "request-header-name")

    for key <- String.graphemes("X-Demo") do
      assert {:noreply, "request-header-name", true} = Breeze.ChildServer.dispatch_input(pid, key)
    end

    assert {:noreply, "request-header-value", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    for key <- String.graphemes("true") do
      assert {:noreply, "request-header-value", true} =
               Breeze.ChildServer.dispatch_input(pid, key)
    end

    assert {:noreply, "request-header-name", true} =
             Breeze.ChildServer.dispatch_input(pid, "Enter")

    assert {:ok, _acc, updated_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    rendered = visible(updated_box.content)

    assert rendered =~ "X-Demo"
    assert rendered =~ "true"
    refute rendered =~ "╱╱╱"
    assert %{focused: "request-header-name"} = Breeze.ChildServer.metadata(pid)
  end

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts) do
      {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    end

    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  test "server input flush loop settles after a focus change" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\t"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      not state.input_flush_scheduled? and state.queued_input == []
    end)

    state = :sys.get_state(pid)

    refute state.input_flush_scheduled?
    assert state.queued_input == []

    Process.exit(pid, :normal)
  end

  test "inspector is opt-in and stays disabled by default" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    assert %{enabled?: false, visible?: false, selected_id: nil} =
             Breeze.Server.inspector_snapshot(pid)

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      not state.input_flush_scheduled? and state.queued_input == []
    end)

    assert %{enabled?: false, visible?: false, selected_id: nil} =
             Breeze.Server.inspector_snapshot(pid)

    Process.exit(pid, :normal)
  end

  test "posting inspector can be toggled and select an element with the mouse" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      snapshot = Breeze.Server.inspector_snapshot(pid)
      snapshot.visible?
    end)

    snapshot = Breeze.Server.inspector_snapshot(pid)
    assert snapshot.enabled?
    assert snapshot.visible?
    assert snapshot.selected_id == "url"

    bounds = :sys.get_state(pid).rendered_mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).selected_id == "method"
    end)

    snapshot = Breeze.Server.inspector_snapshot(pid)
    assert snapshot.selected_id == "method"
    assert snapshot.focused == "url"
    assert snapshot.selected.implicit_module == Breeze.Implicit.Dropdown
    assert snapshot.selected.fragment_preview =~ "POST"

    Process.exit(pid, :normal)
  end

  test "posting inspector can select anonymous non-focusable elements" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).visible?
    end)

    state = :sys.get_state(pid)

    {selected_id, bounds} =
      state.rendered_flags
      |> Enum.filter(fn {key, flags} ->
        String.starts_with?(key, "__inspector__") and Keyword.get(flags, :id) == nil
      end)
      |> Enum.map(fn {key, _flags} -> {key, state.rendered_mouse_targets[key]} end)
      |> Enum.reject(fn {_key, bounds} -> is_nil(bounds) end)
      |> Enum.min_by(fn {_key, bounds} ->
        (bounds.right - bounds.left + 1) * (bounds.bottom - bounds.top + 1)
      end)

    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).selected_id == selected_id
    end)

    snapshot = Breeze.Server.inspector_snapshot(pid)
    assert snapshot.selected_id == selected_id
    assert snapshot.selected.actual_id == nil
    assert is_binary(snapshot.selected.fragment_preview)
    assert is_binary(snapshot.selected.fragment_render)

    Process.exit(pid, :normal)
  end

  test "posting ignores mouse move events when inspector is closed" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        mouse: [mode: :motion],
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    bounds = :sys.get_state(pid).rendered_mouse_targets["url"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<35;#{x};#{y}M"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      Process.alive?(pid) and not state.input_flush_scheduled? and state.queued_input == []
    end)

    assert Process.alive?(pid)
    refute Breeze.Server.inspector_snapshot(pid).visible?

    Process.exit(pid, :normal)
  end

  test "posting inspector dock can move to the top" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).visible?
    end)

    assert %{panel_position: :bottom, move_key: "PageUp"} = Breeze.Server.inspector_snapshot(pid)

    send(pid, {reader, {:data, "\e[5~"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).panel_position == :top
    end)

    assert %{panel_position: :top} = Breeze.Server.inspector_snapshot(pid)

    send(pid, {reader, {:data, "\e[5~"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).panel_position == :bottom
    end)

    assert %{panel_position: :bottom} = Breeze.Server.inspector_snapshot(pid)

    Process.exit(pid, :normal)
  end

  test "posting inspector highlights hovered elements without changing selection" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).visible?
    end)

    initial = Breeze.Server.inspector_snapshot(pid)
    assert initial.selected_id == "url"

    bounds = :sys.get_state(pid).rendered_mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<35;#{x};#{y}M"}})

    wait_until(fn ->
      snapshot = Breeze.Server.inspector_snapshot(pid)
      snapshot.hovered_id == "method"
    end)

    snapshot = Breeze.Server.inspector_snapshot(pid)
    assert snapshot.hovered_id == "method"
    assert snapshot.selected_id == "url"

    Process.exit(pid, :normal)
  end

  test "posting inspector ignores hover events over the inspector panel itself" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).visible?
    end)

    bounds = :sys.get_state(pid).rendered_mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<35;#{x};#{y}M"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).hovered_id == "method"
    end)

    panel_y = terminal.size.height
    panel_x = div(terminal.size.width, 2)

    send(pid, {reader, {:data, "\e[<35;#{panel_x};#{panel_y}M"}})

    Process.sleep(25)

    snapshot = Breeze.Server.inspector_snapshot(pid)
    assert snapshot.hovered_id == "method"
    assert snapshot.selected_id == "url"

    Process.exit(pid, :normal)
  end

  test "posting inspector only cycles outward when clicking the currently selected element again" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).visible?
    end)

    state = :sys.get_state(pid)
    bounds = state.rendered_mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    candidates =
      state.rendered_mouse_targets
      |> Enum.filter(fn {_id, hit_bounds} ->
        x - 1 >= hit_bounds.left and x - 1 <= hit_bounds.right and y - 1 >= hit_bounds.top and
          y - 1 <= hit_bounds.bottom
      end)
      |> Enum.sort_by(fn {_id, hit_bounds} ->
        area = (hit_bounds.right - hit_bounds.left + 1) * (hit_bounds.bottom - hit_bounds.top + 1)
        {area, hit_bounds.top, hit_bounds.left}
      end)
      |> Enum.map(fn {id, _bounds} -> id end)

    parent_id = Enum.at(candidates, 1)
    assert is_binary(parent_id)

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).selected_id == "method"
    end)

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).selected_id == parent_id
    end)

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).selected_id == "method"
    end)

    snapshot = Breeze.Server.inspector_snapshot(pid)
    assert snapshot.selected_id == "method"
    assert snapshot.selected.actual_id == "method"

    Process.exit(pid, :normal)
  end

  test "posting inspector swallows mouse release events instead of bubbling them into the app" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Breeze.Server.inspector_snapshot(pid).visible?
    end)

    bounds = :sys.get_state(pid).rendered_mouse_targets["url"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})
    send(pid, {reader, {:data, "\e[<0;#{x};#{y}m"}})

    wait_until(fn ->
      Process.alive?(pid) and Breeze.Server.inspector_snapshot(pid).visible?
    end)

    assert Process.alive?(pid)
    assert Breeze.Server.inspector_snapshot(pid).visible?

    Process.exit(pid, :normal)
  end

  defp visible(content) do
    String.replace(content, ~r/\e\[[0-9;]*m/u, "")
  end

  defp wait_until(fun, attempts \\ 20)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition not met")
end
