defmodule Breeze.Runtime.StateTest do
  use Breeze.RuntimeTestCase, async: true

  test "state replacement cancels and isolates the previous animation timer" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: AnimatedRoot, terminal: terminal)
    before = :sys.get_state(pid)
    old_timer = before.frame.animation_timer
    old_generation = before.frame.animation_generation

    assert is_reference(old_timer)
    assert is_reference(old_generation)
    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)
    assert :ok = Breeze.Runtime.replace_state(pid, runtime_state)

    restored = :sys.get_state(pid)
    new_timer = restored.frame.animation_timer
    new_generation = restored.frame.animation_generation

    assert Process.read_timer(old_timer) == false
    assert is_reference(new_timer)
    assert is_reference(new_generation)
    refute new_timer == old_timer
    refute new_generation == old_generation

    send(pid, {:animation_tick, old_generation})
    after_stale_tick = :sys.get_state(pid)
    assert after_stale_tick.frame.animation_timer == new_timer
    assert after_stale_tick.frame.animation_generation == new_generation

    stop_gen_server(pid)
  end

  test "runtime state preserves implicit and nested live state in isolated runtimes" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = start_app_server(view: ForkRoot, terminal: terminal, inspector: [remote: false])

    send(pid, {reader, {:data, "i"}})

    wait_until(fn ->
      state = :sys.get_state(pid)

      match?(
        {StatefulImplicit, %{count: 1}},
        Breeze.ChildServer.metadata(state.view_pid).implicit_state["root"]
      )
    end)

    send(pid, {reader, {:data, "+"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      Breeze.ChildServer.metadata(state.view_pid).assigns.count == 1
    end)

    assert {:noreply, "child", true} = Breeze.Server.dispatch_live_input(pid, "child", "+")

    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)

    assert {StatefulImplicit, %{count: 1}} = runtime_state.root.term.implicit_state["root"]
    assert runtime_state.root.term.assigns.count == 1
    assert runtime_state.root.children["child"].state.term.assigns.count == 11
    refute Map.has_key?(runtime_state.root.term.assigns, :__invalidate__)

    send(pid, {reader, {:data, "+"}})
    assert {:noreply, "child", true} = Breeze.Server.dispatch_live_input(pid, "child", "+")

    wait_until(fn ->
      state = :sys.get_state(pid)
      root_count = Breeze.ChildServer.metadata(state.view_pid).assigns.count
      child_count = Breeze.ChildServer.metadata(state.children["child"].pid).assigns.count
      root_count == 2 and child_count == 12
    end)

    assert {:ok, fork} = Breeze.Runtime.start_from_state(runtime_state)
    on_exit(fn -> Breeze.Runtime.stop(fork) end)
    fork_child_pid = :sys.get_state(fork.pid).children["child"].pid

    assert {:ok, snapshot} = Breeze.Runtime.snapshot(fork)
    assert snapshot.content =~ "root=1"
    assert snapshot.content =~ "child=11"

    assert {:noreply, "root", true} = Breeze.Runtime.input(fork, "-")

    assert {:ok, fork_snapshot} = Breeze.Runtime.snapshot(fork)
    assert fork_snapshot.content =~ "root=0"
    assert fork_snapshot.content =~ "child=11"

    assert {:ok, isolated_state} = Breeze.ChildServer.runtime_state(fork.pid)
    assert {StatefulImplicit, %{count: 1}} = isolated_state.term.implicit_state["root"]
    assert isolated_state.term.assigns.count == 0
    assert isolated_state.children["child"].state.term.assigns.count == 11

    state = :sys.get_state(pid)
    assert Breeze.ChildServer.metadata(state.view_pid).assigns.count == 2
    assert Breeze.ChildServer.metadata(state.children["child"].pid).assigns.count == 12

    assert :ok = Breeze.Runtime.stop(fork)
    wait_until(fn -> not Process.alive?(fork_child_pid) end)

    stop_gen_server(pid)
  end

  test "state replacement preserves the server-level live focus path" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: FocusRoot, terminal: terminal)

    assert {:noreply, "child::second", true} =
             Breeze.Server.dispatch_live_input(pid, "child", "x")

    assert :sys.get_state(pid).focused == "child::second"
    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)
    assert runtime_state.focused == "child::second"
    assert runtime_state.root.term.focused == "root"

    assert :ok = Breeze.Runtime.replace_state(pid, runtime_state)

    restored = :sys.get_state(pid)
    assert restored.focused == "child::second"
    assert Breeze.ChildServer.metadata(restored.view_pid).focused == "child::second"
    assert Breeze.ChildServer.metadata(restored.children["child"].pid).focused == "second"

    stop_gen_server(pid)
  end

  test "hidden persistent children survive replacement and isolated startup" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: PersistentRoot, terminal: terminal)

    state = :sys.get_state(pid)
    child_pid = state.children["persistent"].pid

    assert {:noreply, _focused, true} = Breeze.ChildServer.dispatch_input(child_pid, "+")

    wait_until(fn ->
      state = :sys.get_state(pid)
      Breeze.ChildServer.metadata(state.children["persistent"].pid).assigns.count == 11
    end)

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_event(state.view_pid, :toggle, %{})

    wait_until(fn ->
      state = :sys.get_state(pid)

      not Breeze.ChildServer.metadata(state.view_pid).assigns.show_child and
        state.children["persistent"].pid == child_pid
    end)

    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)
    assert runtime_state.root.children["persistent"].persistent

    assert :ok = Breeze.Runtime.replace_state(pid, runtime_state)

    restored = :sys.get_state(pid)
    restored_child_pid = restored.children["persistent"].pid
    assert restored.children["persistent"].persistent
    assert Breeze.ChildServer.metadata(restored_child_pid).assigns.count == 11

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_event(restored.view_pid, :toggle, %{})

    wait_until(fn ->
      state = :sys.get_state(pid)

      state.children["persistent"].pid == restored_child_pid and
        Enum.join(state.frame.last_lines || [], "\n") =~ "child=11"
    end)

    assert {:ok, fork} = Breeze.Runtime.start_from_state(runtime_state)
    on_exit(fn -> Breeze.Runtime.stop(fork) end)

    assert {:ok, hidden_snapshot} = Breeze.Runtime.snapshot(fork)
    refute hidden_snapshot.content =~ "child=11"

    fork_state = :sys.get_state(fork.pid)
    fork_child_pid = fork_state.children["persistent"].pid
    assert fork_state.children["persistent"].persistent
    assert Breeze.ChildServer.metadata(fork_child_pid).assigns.count == 11

    assert {:noreply, _focused, true} = Breeze.Runtime.event(fork, :toggle, %{})
    assert {:ok, shown_snapshot} = Breeze.Runtime.snapshot(fork)
    assert shown_snapshot.content =~ "child=11"
    assert :sys.get_state(fork.pid).children["persistent"].pid == fork_child_pid

    stop_gen_server(pid)
  end

  test "persistent nested children can be captured while their parent is hidden" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: NestedPersistentRoot, terminal: terminal)

    initial = :sys.get_state(pid)
    leaf_pid = initial.children["parent::leaf"].pid
    assert {:noreply, _focused, true} = Breeze.ChildServer.dispatch_input(leaf_pid, "+")

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_event(initial.view_pid, :toggle_parent, %{})

    wait_until(fn ->
      state = :sys.get_state(pid)

      not Map.has_key?(state.children, "parent") and
        state.children["parent::leaf"].pid == leaf_pid
    end)

    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)
    assert runtime_state.root.children["parent::leaf"].persistent
    assert runtime_state.root.children["parent::leaf"].state.term.assigns.count == 1

    assert :ok = Breeze.Runtime.replace_state(pid, runtime_state)
    restored = :sys.get_state(pid)
    restored_leaf_pid = restored.children["parent::leaf"].pid
    assert Breeze.ChildServer.metadata(restored_leaf_pid).assigns.count == 1

    assert {:noreply, _focused, true} =
             Breeze.ChildServer.dispatch_event(restored.view_pid, :toggle_parent, %{})

    wait_until(fn ->
      state = :sys.get_state(pid)

      state.children["parent::leaf"].pid == restored_leaf_pid and
        Enum.join(state.frame.last_lines || [], "\n") =~ "nested=1"
    end)

    stop_gen_server(pid)
  end

  test "replacement errors clean up the root and children started before the failure" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: RestoreChildrenRoot, terminal: terminal)
    supervisor = :sys.get_state(pid).child_view_supervisor
    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)

    invalid_child = %{runtime_state.root.children["b"] | view: FocusChild}

    invalid_state = %{
      runtime_state
      | root: %{
          runtime_state.root
          | children: Map.put(runtime_state.root.children, "b", invalid_child)
        }
    }

    assert {:error, {"b", _reason}} = Breeze.Runtime.replace_state(pid, invalid_state)

    failed = :sys.get_state(pid)
    assert failed.view_pid == nil
    assert failed.children == %{}
    assert failed.crash
    assert %{active: 0} = DynamicSupervisor.count_children(supervisor)

    stop_gen_server(pid)
  end

  test "isolated runtime theme overrides apply to restored descendants" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: ForkRoot, terminal: terminal)

    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)
    override = Breeze.Theme.builtin(:gruvbox)
    assert {:ok, fork} = Breeze.Runtime.start_from_state(runtime_state, theme: override)
    on_exit(fn -> Breeze.Runtime.stop(fork) end)

    root = :sys.get_state(fork.pid)
    child = :sys.get_state(root.children["child"].pid)

    assert root.theme == override
    assert root.theme_source == override
    assert child.theme == override
    assert child.theme_source == override
    assert root.apply_theme_defaults?
    assert child.apply_theme_defaults?

    stop_gen_server(pid)
  end

  test "starting from runtime state does not rerun mount side effects" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: MountSideEffectView,
        start_opts: [owner: self()],
        terminal: terminal
      )

    assert_receive {:mounted, source_view_pid}
    assert is_pid(source_view_pid)

    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)
    assert {:ok, fork} = Breeze.Runtime.start_from_state(runtime_state)
    on_exit(fn -> Breeze.Runtime.stop(fork) end)

    refute_received {:mounted, _fork_view_pid}
    assert {:ok, snapshot} = Breeze.Runtime.snapshot(fork)
    assert snapshot.content =~ "count=7"

    stop_gen_server(pid)
  end
end
