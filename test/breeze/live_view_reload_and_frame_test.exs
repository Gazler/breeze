defmodule Breeze.LiveView.ReloadAndFrameTest do
  use Breeze.TestSupport.LiveViewCase, async: true

  test "server rerenders the current root view when the code reloader detects changes" do
    parent = self()
    path = make_reload_fixture_path("reload")
    File.write!(path, "initial\n")

    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: ReloadableView,
        terminal: terminal,
        start_opts: [parent: self()],
        reload: [
          force?: true,
          paths: [Path.dirname(path)],
          watcher_module: FakeWatcher,
          compile_fun: fn files ->
            send(parent, {:compiled_files, files})
            :ok
          end
        ]
      )

    assert_receive :reloadable_view_mounted, 1_000

    added_path = Path.join(Path.dirname(path), "changed.ex")
    File.write!(added_path, "changed\n")
    reloader_pid = :sys.get_state(pid).reloader_pid
    watcher_pid = :sys.get_state(reloader_pid).watcher_pid
    reloader_ref = Process.monitor(reloader_pid)
    watcher_ref = Process.monitor(watcher_pid)
    :ok = FakeWatcher.trigger(watcher_pid, added_path)

    assert_receive {:compiled_files, files}, 1_000
    assert added_path in files

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug.stats[:last_render_cause] == :reload and state.frame.base_output =~ "ready"
    end)

    stop_gen_server(pid)
    assert_receive {:DOWN, ^reloader_ref, :process, ^reloader_pid, :shutdown}, 500
    assert_receive {:DOWN, ^watcher_ref, :process, ^watcher_pid, :shutdown}, 500
  end

  test "debug pane does not flash an empty stats snapshot on first open" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: DebugToggleRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    set_debug_push_interval(pid, 20)
    drain_terminal_writes()

    send(pid, {reader, {:data, "\eOQ"}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    output = IO.iodata_to_binary(writes)

    refute output =~ "cause: -"
    refute output =~ "renders: 0 (0/s)"

    stop_gen_server(pid)
  end

  test "server enters the crash screen when reloading hits a compile error" do
    capture_log(fn ->
      parent = self()
      path = make_reload_fixture_path("compile_error")
      File.write!(path, "initial\n")

      on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} =
        start_app_server(
          view: ReloadableView,
          terminal: terminal,
          start_opts: [parent: self()],
          reload: [
            force?: true,
            paths: [Path.dirname(path)],
            watcher_module: FakeWatcher,
            compile_fun: fn _files ->
              send(parent, :reload_compile_attempted)
              {:error, CompileError.exception(description: "reload failed")}
            end
          ]
        )

      assert_receive :reloadable_view_mounted, 1_000

      broken_path = Path.join(Path.dirname(path), "broken.ex")
      File.write!(broken_path, "broken\n")
      watcher_pid = :sys.get_state(:sys.get_state(pid).reloader_pid).watcher_pid
      :ok = FakeWatcher.trigger(watcher_pid, broken_path)
      assert_receive :reload_compile_attempted, 1_000

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "reload failed"
      end)

      state = :sys.get_state(pid)
      assert state.crash
      assert state.frame.base_output =~ "Breeze Error"
      assert state.frame.base_output =~ "reload failed"

      stop_gen_server(pid)
    end)
  end

  test "server preserves state while refreshing example-style root global keybindings on reload" do
    {:ok, config_pid} =
      Agent.start_link(fn ->
        [
          view: ReloadConfigView,
          global_keybindings: [
            {"x",
             fn _event, term ->
               {:noreply, Breeze.View.assign(term, count: term.assigns.count + 1)}
             end}
          ]
        ]
      end)

    refresh = fn ->
      Agent.get(config_pid, & &1)
    end

    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: ReloadConfigView,
        terminal: terminal,
        reader: reader,
        global_keybindings: refresh.()[:global_keybindings],
        reload: [
          force?: true,
          watcher_module: FakeWatcher,
          refresh_server_opts: {__MODULE__, :reload_config_server_opts, [refresh]}
        ]
      )

    send(pid, {reader, {:data, "x"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.frame.base_output =~ "Count: 1"
    end)

    Agent.update(config_pid, fn _opts ->
      [
        view: ReloadConfigView,
        global_keybindings: [
          {"y",
           fn _event, term ->
             {:noreply, Breeze.View.assign(term, count: term.assigns.count + 1)}
           end}
        ]
      ]
    end)

    send(pid, {:reload, :code_changed, ["lib/breeze/view.ex"]})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug.stats[:last_render_cause] == :reload and state.frame.base_output =~ "Count: 1"
    end)

    wait_until(fn ->
      state = :sys.get_state(pid)

      match?(
        [{"y", _fun}],
        state.input.global_keybindings
      )
    end)

    send(pid, {reader, {:data, "y"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.frame.base_output =~ "Count: 2"
    end)

    stop_gen_server(pid)
  end

  test "refresh_server_opts can receive root metadata and preserve state on reload restart" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: ReloadStateView,
        terminal: terminal,
        reader: reader,
        reload: [
          force?: true,
          watcher_module: FakeWatcher,
          refresh_server_opts: {__MODULE__, :reload_state_server_opts, []}
        ]
      )

    send(pid, {reader, {:data, "x"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.frame.base_output =~ "Count: 1"
    end)

    send(pid, {:reload, :code_changed, ["lib/breeze/view.ex"]})

    wait_until(fn ->
      state = :sys.get_state(pid)

      state.debug.stats[:last_render_cause] == :reload and
        state.start_opts == [count: 1] and
        state.frame.base_output =~ "Count: 1"
    end)

    stop_gen_server(pid)
  end

  test "reloaded root global keybindings do not corrupt nested live child state" do
    {:ok, config_pid} =
      Agent.start_link(fn ->
        [
          view: RootReloadWithNestedChild,
          global_keybindings: [
            {"x",
             fn _event, term ->
               {:noreply, Breeze.View.assign(term, count: term.assigns.count + 1)}
             end}
          ]
        ]
      end)

    refresh = fn ->
      Agent.get(config_pid, & &1)
    end

    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: RootReloadWithNestedChild,
        terminal: terminal,
        reader: reader,
        global_keybindings: refresh.()[:global_keybindings],
        reload: [
          force?: true,
          watcher_module: FakeWatcher,
          refresh_server_opts: {__MODULE__, :reload_config_server_opts, [refresh]}
        ]
      )

    nested_pid =
      wait_until(fn ->
        state = :sys.get_state(pid)

        case state.children["nested"] do
          %{pid: nested_pid} -> nested_pid
          _ -> nil
        end
      end)

    :ok = Breeze.ChildServer.update_assigns(nested_pid, reload_marker: :preserved)

    wait_until(fn ->
      state = :sys.get_state(pid)

      :sys.get_state(nested_pid).assigns.reload_marker == :preserved and
        Map.has_key?(state.children, "nested")
    end)

    Agent.update(config_pid, fn _opts ->
      [
        view: RootReloadWithNestedChild,
        global_keybindings: [
          {"4",
           fn _event, term ->
             {:noreply, Breeze.View.assign(term, count: term.assigns.count + 1)}
           end}
        ]
      ]
    end)

    send(pid, {:reload, :code_changed, ["lib/breeze/view.ex"]})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug.stats[:last_render_cause] == :reload
    end)

    send(pid, {reader, {:data, "4"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.frame.base_output =~ "Count: 1"
    end)

    nested = :sys.get_state(pid).children["nested"]
    nested_term = :sys.get_state(nested.pid)

    assert nested.pid == nested_pid
    assert nested_term.assigns.reload_marker == :preserved

    stop_gen_server(pid)
  end

  test "debug stats updates do not invalidate the parent just to refresh the pane" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: DebugToggleRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    drain_terminal_writes()

    send(pid, {reader, {:data, "\eOQ"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      Map.has_key?(state.children, "debug")
    end)

    flush_debug_stats(pid)
    drain_terminal_writes()

    invalidations_before = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    flush_debug_stats(pid)
    writes = drain_terminal_writes()
    invalidations_after = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    assert writes == []
    assert invalidations_after == invalidations_before

    stop_gen_server(pid)
  end

  test "server falls back to a full rerender when a debug child has decorations" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
        view: DecoratedDebugRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    wait_until(fn ->
      state = :sys.get_state(pid)
      if Map.has_key?(state.children, "debug"), do: state, else: false
    end)

    state = :sys.get_state(pid)
    initial_render_count = state.debug.stats[:render_base_count]
    child = state.children["debug"]

    drain_terminal_writes()

    assert {:noreply, "button", true} = Breeze.ChildServer.dispatch_input(child.pid, "+")

    wait_until(fn ->
      next_state = :sys.get_state(pid)
      next_state.debug.stats[:render_base_count] > initial_render_count
    end)

    next_state = :sys.get_state(pid)

    assert next_state.debug.stats[:render_base_count] > initial_render_count
    assert next_state.debug.stats[:last_render_cause] == :child_invalidated

    stop_gen_server(pid)
  end

  test "child patch payload starts at the live root even when the live placeholder has no explicit size" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
        view: HeaderedLiveRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    wait_until(fn ->
      state = :sys.get_state(pid)
      Map.has_key?(state.children, "child")
    end)

    child = :sys.get_state(pid).children["child"]
    drain_terminal_writes()

    assert {:noreply, nil} = Breeze.ChildServer.dispatch_info(child.pid, :bump, terminal)

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug.stats[:last_render_cause] == :child_patch
    end)

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    assert Enum.any?(writes, &String.starts_with?(&1, "\e[3;1H"))
    refute Enum.any?(writes, &String.starts_with?(&1, "\e[5;1H"))

    stop_gen_server(pid)
  end

  test "sibling live child patch payload starts at the invalidated child viewport" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
        view: InlineLivePatchRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    wait_until(fn ->
      state = :sys.get_state(pid)
      Map.has_key?(state.children, "right") and Map.has_key?(state.rendered.elements, "right")
    end)

    state = :sys.get_state(pid)
    right = state.children["right"]
    viewport = state.rendered.elements["right"]
    assert viewport.left > 0
    drain_terminal_writes()

    assert {:noreply, _focused, true} = Breeze.ChildServer.dispatch_input(right.pid, "+")

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug.stats[:last_render_cause] == :child_patch
    end)

    payload =
      wait_until(fn ->
        writes = drain_terminal_writes()
        payload = IO.iodata_to_binary(writes)

        if payload =~ "Count: 2" do
          payload
        else
          false
        end
      end)

    expected_position = "\e[#{viewport.top + 1};#{viewport.left + 1}H"
    refute String.contains?(payload, "\e[#{viewport.top + 1};1H")
    assert String.contains?(payload, expected_position)

    stop_gen_server(pid)
  end

  test "winch forces a full redraw to resync the compositor" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: CounterChild,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    drain_terminal_writes()

    send(pid, {reader, {:signal, :winch}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if writes == [], do: false, else: writes
      end)

    payload = IO.iodata_to_binary(writes)

    assert payload =~ "\e[2J\e[H"

    stop_gen_server(pid)
  end

  test "terminal size override is reapplied after resize" do
    terminal = Termite.Terminal.start(adapter: ResizeAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
        view: CounterChild,
        terminal: terminal,
        internal: [
          terminal_size_override: fn size -> %{size | height: max(size.height - 1, 1)} end
        ]
      )

    assert :sys.get_state(pid).terminal.size == %{width: 120, height: 66}

    send(pid, {terminal.reader, {:signal, :winch}})

    wait_until(fn ->
      case :sys.get_state(pid).debug.stats[:last_render_cause] do
        :resize -> true
        _ -> false
      end
    end)

    assert :sys.get_state(pid).terminal.size == %{width: 120, height: 66}

    stop_gen_server(pid)
  end

  test "incremental frame diff writes rows introduced by a height increase" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} = start_app_server(view: GrowingRoot, terminal: terminal)

    drain_terminal_writes()

    :sys.replace_state(pid, fn state ->
      terminal = %{state.terminal | size: %{state.terminal.size | height: 26}}
      frame = %{state.frame | last_payload: nil}
      %{state | terminal: terminal, frame: frame}
    end)

    send(pid, {terminal.reader, {:data, "+"}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        payload = IO.iodata_to_binary(writes)

        if payload =~ "\e[25;1H" and payload =~ "\e[26;1H" do
          writes
        else
          false
        end
      end)

    payload = IO.iodata_to_binary(writes)
    assert payload =~ "row 25"
    assert payload =~ "row 26"

    stop_gen_server(pid)
  end

  test "debug pane invalidation settles instead of feeding back into its own stats stream" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: DebugPaneRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    set_debug_push_interval(pid, 20)
    drain_terminal_writes()
    initial_render_count = :sys.get_state(pid).debug.stats[:render_base_count] || 0

    send(pid, {reader, {:data, "+"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      (state.debug.stats[:render_base_count] || 0) > initial_render_count
    end)

    flush_debug_stats(pid)
    drain_terminal_writes()

    invalidations_before = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    flush_debug_stats(pid)
    writes = drain_terminal_writes()
    invalidations_after = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    assert writes == []
    assert invalidations_after == invalidations_before

    stop_gen_server(pid)
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

  test "global stop keybindings win over inspector movement keys" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: CounterChild,
        terminal: terminal,
        global_keybindings: [{"F10", fn _event, term -> {:stop, term} end}]
      )

    ref = Process.monitor(pid)

    send(pid, {reader, {:data, "\e[21~"}})

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  defp set_debug_push_interval(pid, interval) do
    :sys.replace_state(pid, fn state ->
      %{state | debug: %{state.debug | push_interval_ms: interval}}
    end)
  end

  defp flush_debug_stats(pid) do
    send(pid, :debug_push)
    state = :sys.get_state(pid)
    debug_pid = state.children["debug"].pid
    _ = :sys.get_state(debug_pid)
    _ = :sys.get_state(pid)
    :ok
  end

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      2 -> Enum.reverse(writes)
    end
  end

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(fun, attempts) when attempts > 0 do
    case fun.() do
      false ->
        Process.sleep(2)
        wait_until(fun, attempts - 1)

      nil ->
        Process.sleep(2)
        wait_until(fun, attempts - 1)

      value ->
        value
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition not met")

  defp make_reload_fixture_path(label) do
    dir =
      Path.join(System.tmp_dir!(), "breeze-reload-#{label}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    Path.join(dir, "watched.ex")
  end

  def reload_config_server_opts(refresh) when is_function(refresh, 0) do
    refresh.()
  end

  def reload_state_server_opts(%{metadata: %{assigns: assigns}}) do
    [start_opts: [count: assigns.count]]
  end

  test "server restarts a live child when its view changes" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} = start_app_server(view: SwitchableLiveRoot, terminal: terminal)

    on_exit(fn -> stop_gen_server(pid) end)

    drain_terminal_writes()
    previous_child = :sys.get_state(pid).children["preview"].pid

    send(pid, {terminal.reader, {:data, "s"}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if IO.iodata_to_binary(writes) =~ "Alternate child", do: writes, else: false
      end)

    assert IO.iodata_to_binary(writes) =~ "Alternate child"
    refute Process.alive?(previous_child)
    assert :sys.get_state(pid).children["preview"].pid != previous_child
  end
end
