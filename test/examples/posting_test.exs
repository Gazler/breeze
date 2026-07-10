defmodule PostingTest do
  use ExUnit.Case, async: true
  import Breeze.TestSupport.WaitUntil

  alias Breeze.Server.Diagnostics

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
    assert visible(open_box.content) =~ "▲"

    assert {Breeze.Implicit.Dropdown, %{open?: true}} =
             Breeze.ChildServer.metadata(pid).implicit_state["method"]
  end

  test "Ctrl-T opens the method dropdown when the url input is focused via decoded key event" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert %{focused: "url"} = Breeze.ChildServer.metadata(pid)

    assert {:noreply, "method", true} =
             Breeze.ChildServer.dispatch_input(pid, %{"ctrlKey" => true, "key" => "t"})

    assert {:ok, _acc, open_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(open_box.content) =~ "GET"
    assert visible(open_box.content) =~ "▲"

    assert {Breeze.Implicit.Dropdown, %{open?: true}} =
             Breeze.ChildServer.metadata(pid).implicit_state["method"]
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

  test "header input implicit state survives switching tabs away and back" do
    terminal = %Termite.Terminal{size: %{width: 120, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    assert {:noreply, "request-header-name", true} =
             Breeze.ChildServer.set_focus(pid, "request-header-name")

    for key <- String.graphemes("ABCDE") do
      assert {:noreply, "request-header-name", true} = Breeze.ChildServer.dispatch_input(pid, key)
    end

    assert {:noreply, "request-header-name", true} =
             Breeze.ChildServer.dispatch_input(pid, "ArrowLeft")

    assert {:noreply, "request-header-name", true} =
             Breeze.ChildServer.dispatch_input(pid, "ArrowLeft")

    assert {Breeze.Implicit.Input, %{cursor: 3}} =
             Breeze.ChildServer.metadata(pid).implicit_state["request-header-name"]

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_event(pid, "request_tab", %{value: "body"})

    assert {:ok, _acc, body_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(body_box.content) =~ "No request body"

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_event(pid, "request_tab", %{value: "headers"})

    assert {:ok, _acc, headers_box} = Breeze.ChildServer.render(pid, terminal: terminal)
    assert visible(headers_box.content) =~ "ABCDE"

    assert {Breeze.Implicit.Input, %{cursor: 3}} =
             Breeze.ChildServer.metadata(pid).implicit_state["request-header-name"]
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

  defmodule RecordingAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{ref: make_ref(), size: %{width: 80, height: 24}, owner: Keyword.fetch!(opts, :owner)}}
    end

    def reader(term), do: {:ok, term.ref}

    def write(term, str) do
      send(term.owner, {:terminal_write, str})
      {:ok, term}
    end

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
      not state.input.flush_scheduled? and :queue.is_empty(state.input.queued_input)
    end)

    state = :sys.get_state(pid)

    refute state.input.flush_scheduled?
    assert :queue.is_empty(state.input.queued_input)

    Process.exit(pid, :normal)
  end

  test "server drains a burst of printable input for posting" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    Enum.each(1..100, fn _ -> send(pid, {reader, {:data, "x"}}) end)

    wait_until(fn ->
      state = :sys.get_state(pid)
      term = :sys.get_state(state.view_pid)

      not state.input.flush_scheduled? and :queue.is_empty(state.input.queued_input) and
        String.ends_with?(term.assigns.url, String.duplicate("x", 100))
    end)

    state = :sys.get_state(pid)
    term = :sys.get_state(state.view_pid)

    assert :queue.is_empty(state.input.queued_input)
    assert String.ends_with?(term.assigns.url, String.duplicate("x", 100))

    Process.exit(pid, :normal)
  end

  test "server forwards ctrl-backspace variants to the focused posting input" do
    for raw_key <- [
          "\b",
          "\e[8;5u",
          "\e[127;5u",
          "\e[27;5;8u",
          "\e[27;5;127u",
          "\e[27;5;127~",
          "\e[127;5~"
        ] do
      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} =
        Breeze.Server.start_link(
          view: Posting,
          alt_screen: false,
          enhanced_keyboard: false,
          hide_cursor: false,
          terminal: terminal,
          halt_fun: fn -> :ok end,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      state = :sys.get_state(pid)
      reader = state.reader
      server_pid = state.server_pid

      send(pid, {reader, {:data, raw_key}})

      wait_until(fn ->
        state = :sys.get_state(server_pid)
        term = :sys.get_state(state.view_pid)

        not state.input.flush_scheduled? and :queue.is_empty(state.input.queued_input) and
          term.assigns.url == ""
      end)

      GenServer.stop(pid, :normal)
    end
  end

  test "posting keeps repeated wide characters contiguous in the url row" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = Breeze.ChildServer.start(view: Posting, terminal: terminal)

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(pid, terminal: terminal)

    for key <- String.graphemes(String.duplicate("好", 6)) do
      assert {:noreply, "url", true} = Breeze.ChildServer.dispatch_input(pid, key)
    end

    assert {:ok, _acc, box} = Breeze.ChildServer.render(pid, terminal: terminal)

    url_row =
      box.content
      |> visible()
      |> String.split("\n")
      |> Enum.at(3)

    assert url_row =~ "posts好好好好好好"
  end

  test "server accepts a multi-grapheme wide-character paste in the url row" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    wait_until(fn ->
      state = :sys.get_state(pid)
      not is_nil(state.frame.base_output)
    end)

    drain_terminal_writes()

    send(pid, {reader, {:data, "こんにちは"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      term = :sys.get_state(state.view_pid)

      not state.input.flush_scheduled? and :queue.is_empty(state.input.queued_input) and
        String.ends_with?(term.assigns.url, "こんにちは")
    end)

    state = :sys.get_state(pid)
    row = state.frame.base_output |> String.split("\n") |> Enum.at(3)

    assert visible(row) =~ "postsこんにちは"
    assert BackBreeze.Utils.string_length(row) == terminal.size.width

    blank_panel_row =
      state.frame.base_output
      |> String.split("\n")
      |> Enum.find(&(visible(&1) =~ "│                                    ││"))

    assert blank_panel_row
    assert visible(blank_panel_row) =~ "│                                    ││"
    refute blank_panel_row =~ "│                                    ││"

    payload = drain_terminal_writes() |> IO.iodata_to_binary()
    assert payload =~ "postsこんにちは"

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
             Diagnostics.inspector_snapshot(pid)

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      not state.input.flush_scheduled? and :queue.is_empty(state.input.queued_input)
    end)

    assert %{enabled?: false, visible?: false, selected_id: nil} =
             Diagnostics.inspector_snapshot(pid)

    Process.exit(pid, :normal)
  end

  defp visible(content) do
    String.replace(content, ~r/\e\[[0-9;]*m/u, "")
  end

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end
end

defmodule PostingInspectorTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.WaitUntil

  alias Breeze.Server.Diagnostics
  alias PostingTest.{FakeAdapter, RecordingAdapter}

  test "posting inspector can be toggled and select an element with the mouse" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      snapshot = Diagnostics.inspector_snapshot(pid)
      snapshot.visible?
    end)

    snapshot = Diagnostics.inspector_snapshot(pid)
    assert snapshot.enabled?
    assert snapshot.visible?
    assert snapshot.selected_id == "url"

    bounds = :sys.get_state(pid).rendered.mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).selected_id == "method"
    end)

    snapshot = Diagnostics.inspector_snapshot(pid)
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
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).visible?
    end)

    state = :sys.get_state(pid)

    {selected_id, bounds} =
      state.rendered.flags
      |> Enum.filter(fn {key, flags} ->
        String.starts_with?(key, "__inspector__") and Keyword.get(flags, :id) == nil
      end)
      |> Enum.map(fn {key, _flags} -> {key, state.rendered.mouse_targets[key]} end)
      |> Enum.reject(fn {_key, bounds} -> is_nil(bounds) end)
      |> Enum.min_by(fn {_key, bounds} ->
        (bounds.right - bounds.left + 1) * (bounds.bottom - bounds.top + 1)
      end)

    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).selected_id == selected_id
    end)

    snapshot = Diagnostics.inspector_snapshot(pid)
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
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    bounds = :sys.get_state(pid).rendered.mouse_targets["url"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<35;#{x};#{y}M"}})

    wait_until(fn ->
      state = :sys.get_state(pid)

      Process.alive?(pid) and not state.input.flush_scheduled? and
        :queue.is_empty(state.input.queued_input)
    end)

    assert Process.alive?(pid)
    refute Diagnostics.inspector_snapshot(pid).visible?

    Process.exit(pid, :normal)
  end

  test "posting inspector dock can move to the top" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).visible?
    end)

    assert %{panel_position: :bottom, move_key: "PageUp"} =
             Diagnostics.inspector_snapshot(pid)

    drain_terminal_writes()

    send(pid, {reader, {:data, "\e[5~"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).panel_position == :top
    end)

    assert %{panel_position: :top} = Diagnostics.inspector_snapshot(pid)
    assert_terminal_repaired_row(24 - Breeze.Inspector.panel_height())

    send(pid, {reader, {:data, "\e[5~"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).panel_position == :bottom
    end)

    assert %{panel_position: :bottom} = Diagnostics.inspector_snapshot(pid)
    assert_terminal_repaired_row(0)

    Process.exit(pid, :normal)
  end

  test "posting inspector highlights hovered elements without changing selection" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: Posting,
        terminal: terminal,
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).visible?
    end)

    initial = Diagnostics.inspector_snapshot(pid)
    assert initial.selected_id == "url"

    bounds = :sys.get_state(pid).rendered.mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<35;#{x};#{y}M"}})

    wait_until(fn ->
      snapshot = Diagnostics.inspector_snapshot(pid)
      snapshot.hovered_id == "method"
    end)

    snapshot = Diagnostics.inspector_snapshot(pid)
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
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).visible?
    end)

    bounds = :sys.get_state(pid).rendered.mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<35;#{x};#{y}M"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).hovered_id == "method"
    end)

    panel_y = terminal.size.height
    panel_x = div(terminal.size.width, 2)

    send(pid, {reader, {:data, "\e[<35;#{panel_x};#{panel_y}M"}})

    Process.sleep(25)

    snapshot = Diagnostics.inspector_snapshot(pid)
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
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).visible?
    end)

    state = :sys.get_state(pid)
    bounds = state.rendered.mouse_targets["method"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    candidates =
      state.rendered.mouse_targets
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
      Diagnostics.inspector_snapshot(pid).selected_id == "method"
    end)

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).selected_id == parent_id
    end)

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).selected_id == "method"
    end)

    snapshot = Diagnostics.inspector_snapshot(pid)
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
        inspector: [remote: false],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOS"}})

    wait_until(fn ->
      Diagnostics.inspector_snapshot(pid).visible?
    end)

    bounds = :sys.get_state(pid).rendered.mouse_targets["url"]
    x = div(bounds.left + bounds.right, 2) + 1
    y = div(bounds.top + bounds.bottom, 2) + 1

    send(pid, {reader, {:data, "\e[<0;#{x};#{y}M"}})
    send(pid, {reader, {:data, "\e[<0;#{x};#{y}m"}})

    wait_until(fn ->
      Process.alive?(pid) and Diagnostics.inspector_snapshot(pid).visible?
    end)

    assert Process.alive?(pid)
    assert Diagnostics.inspector_snapshot(pid).visible?

    Process.exit(pid, :normal)
  end

  defp assert_terminal_repaired_row(zero_based_row) do
    payload =
      drain_terminal_writes()
      |> IO.iodata_to_binary()

    assert payload =~ "\e[#{zero_based_row + 1};1H"
  end

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end
end
