defmodule Breeze.Runtime.FrameTest do
  use Breeze.RuntimeTestCase, async: true

  test "runtime capture stays disabled unless an hook is configured" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = start_app_server(view: ForkRoot, terminal: terminal)

    assert :sys.get_state(pid).rendered.runtime_hooks == []
    refute_received {:hook_event, _, _}

    capture_mfa = {Breeze.Runtime.State, :capture_server, 2}
    :erlang.trace_pattern(capture_mfa, true, [:local])
    :erlang.trace(pid, true, [:call])

    try do
      send(pid, {reader, {:data, "+"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        Breeze.ChildServer.metadata(state.view_pid).assigns.count == 1
      end)

      refute_received {:trace, ^pid, :call, {Breeze.Runtime.State, :capture_server, _arguments}}
    after
      :erlang.trace(pid, false, [:call])
      :erlang.trace_pattern(capture_mfa, false, [:local])
    end

    stop_gen_server(pid)
  end

  test "a captured frame can be displayed in the source application and restored" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = start_app_server(view: ForkRoot, terminal: terminal)

    initial = :sys.get_state(pid)
    root_pid = initial.view_pid
    child_pid = initial.children["child"].pid

    assert :ok =
             Breeze.Runtime.display_frame(
               pid,
               %{width: 80, height: 24, lines: ["historical frame"]},
               owner: self()
             )

    displayed = :sys.get_state(pid)
    assert displayed.frame.display.lines == ["historical frame"]
    assert hd(displayed.frame.last_lines) == "historical frame"
    assert root_pid in displayed.frame.display_suspended_pids
    assert child_pid in displayed.frame.display_suspended_pids
    assert {:error, :frame_display_active} = Breeze.Runtime.capture_state(pid)

    send(pid, {reader, {:data, "+"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      :queue.is_empty(state.input.queued_input) and not state.input.flush_scheduled?
    end)

    assert :ok = Breeze.Runtime.display_frame(pid, :live)

    wait_until(fn ->
      state = :sys.get_state(pid)

      is_nil(state.frame.display) and
        Breeze.ChildServer.metadata(state.view_pid).assigns.count == 0 and
        Enum.join(state.frame.last_lines || [], "\n") =~ "root=0"
    end)

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert :ok = Breeze.Runtime.display_frame(pid, %{lines: ["owned frame"]}, owner: owner)

    assert :sys.get_state(pid).frame.display_owner == owner
    Process.exit(owner, :kill)

    wait_until(fn ->
      state = :sys.get_state(pid)
      is_nil(state.frame.display) and state.frame.display_suspended_pids == []
    end)

    stop_gen_server(pid)
  end

  test "a timed out suspension is still resumed when returning to the live frame" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: BlockingView,
        start_opts: [owner: self()],
        terminal: terminal,
        internal: [frame_display_sys_timeout: 10]
      )

    view_pid = :sys.get_state(pid).view_pid
    send(view_pid, {:block, self()})
    assert_receive {:view_blocked, ^view_pid}

    assert :ok = Breeze.Runtime.display_frame(pid, %{lines: ["paused"]})
    assert view_pid in :sys.get_state(pid).frame.display_suspended_pids

    send(view_pid, :unblock)
    assert :ok = Breeze.Runtime.display_frame(pid, :live)
    assert %{view: BlockingView} = Breeze.ChildServer.metadata(view_pid)

    stop_gen_server(pid)
  end

  test "historical frames replay overlays and fit captured rows to the current width" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self(), size: {4, 2})
    {:ok, pid} = start_app_server(view: ForkRoot, terminal: terminal)

    drain_terminal_writes()
    overlay = %{x: 1, y: 0, content: "O", no_wrap: true}

    assert :ok =
             Breeze.Runtime.display_frame(pid, %{
               width: 8,
               height: 2,
               lines: ["abcdefgh", "wxyz1234"],
               overlays: [overlay]
             })

    displayed = :sys.get_state(pid)
    assert displayed.frame.display.overlays == [overlay]
    assert displayed.frame.last_lines == ["abcd", "wxyz"]
    assert displayed.frame.last_overlays == [overlay]

    payload = drain_terminal_writes() |> IO.iodata_to_binary()
    assert payload =~ "\e[1;2H\e[?7lO\e[?7h\e[1;2H"
    refute payload =~ "efgh"
    refute payload =~ "1234"

    assert {:error, :invalid_frame} =
             Breeze.Runtime.display_frame(pid, %{
               lines: ["invalid overlay"],
               overlays: [%{x: "bad", y: 0, content: "x"}]
             })

    stop_gen_server(pid)
  end

  test "runtime state can replace the source runtime and resume on the next input" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = start_app_server(view: ForkRoot, terminal: terminal)

    send(pid, {reader, {:data, "+"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      Breeze.ChildServer.metadata(state.view_pid).assigns.count == 1
    end)

    state = :sys.get_state(pid)

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_input(state.children["child"].pid, "+")

    wait_until(fn ->
      state = :sys.get_state(pid)
      Breeze.ChildServer.metadata(state.children["child"].pid).assigns.count == 11
    end)

    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)

    send(pid, {reader, {:data, "+"}})
    state = :sys.get_state(pid)

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_input(state.children["child"].pid, "+")

    wait_until(fn ->
      state = :sys.get_state(pid)

      Breeze.ChildServer.metadata(state.view_pid).assigns.count == 2 and
        Breeze.ChildServer.metadata(state.children["child"].pid).assigns.count == 12
    end)

    old_state = :sys.get_state(pid)

    assert :ok = Breeze.Runtime.replace_state(pid, runtime_state)
    assert :ok = Breeze.Runtime.pause(pid)

    restored = :sys.get_state(pid)
    refute restored.view_pid == old_state.view_pid
    refute restored.children["child"].pid == old_state.children["child"].pid
    assert restored.frame.resume_on_input?
    assert restored.frame.display.lines == restored.frame.last_lines
    assert restored.view_pid in restored.frame.display_suspended_pids
    assert restored.children["child"].pid in restored.frame.display_suspended_pids
    assert Enum.join(restored.frame.last_lines, "\n") =~ "root=1"
    assert Enum.join(restored.frame.last_lines, "\n") =~ "child=11"

    send(pid, {reader, {:data, "-"}})

    wait_until(fn ->
      state = :sys.get_state(pid)

      not state.frame.resume_on_input? and is_nil(state.frame.display) and
        Breeze.ChildServer.metadata(state.view_pid).assigns.count == 0 and
        Breeze.ChildServer.metadata(state.children["child"].pid).assigns.count == 11
    end)

    assert :ok = Breeze.Runtime.replace_state(pid, runtime_state)
    assert :ok = Breeze.Runtime.pause(pid)

    assert {:noreply, _focused, true} =
             Breeze.Server.dispatch_live_input(pid, "child", "-")

    wait_until(fn ->
      state = :sys.get_state(pid)

      not state.frame.resume_on_input? and is_nil(state.frame.display) and
        Breeze.ChildServer.metadata(state.view_pid).assigns.count == 1 and
        Breeze.ChildServer.metadata(state.children["child"].pid).assigns.count == 10
    end)

    stop_gen_server(pid)
  end
end
