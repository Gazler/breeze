defmodule Breeze.Runtime.HooksTest do
  use Breeze.RuntimeTestCase, async: true

  test "configured hooks lazily capture runtime state and diagnostics" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: ForkRoot,
        terminal: terminal,
        inspector: [remote: false],
        runtime_hooks: [{CaptureHook, owner: self(), every: 2}]
      )

    assert_receive {:hook_init, %{view: ForkRoot}}
    assert_receive {:hook_event, 1, %{cause: :unknown, mode: :full}}
    refute_received {:hook_capture, _, _, _, _}

    reader = terminal.reader
    send(pid, {reader, {:data, "+"}})

    assert_receive {:hook_event, 2, %{mode: :full}}, 500

    assert_receive {:hook_capture, :rendered, {:ok, runtime_state}, metadata, diagnostics}, 500

    assert metadata.server_pid == pid
    assert runtime_state.view == ForkRoot
    assert is_list(diagnostics.frame.lines)
    assert diagnostics.inspector.enabled?

    assert %{state: %{term: %Breeze.Term{view: ForkChild}}} = runtime_state.root.children["child"]

    stop_gen_server(pid)
  end

  test "configured inspector pages contribute runtime hooks" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: ForkRoot,
        terminal: terminal,
        inspector: [
          remote: false,
          pages: [{HookPage, owner: self(), id: :page}]
        ]
      )

    assert_receive {:tagged_hook_init, :page, %{view: ForkRoot}}
    assert_receive {:tagged_hook_event, :page, 1, %{mode: :full}}

    assert_receive {:tagged_hook_capture, :page, 1, :rendered, {:ok, _runtime_state}, _, _}

    assert [%Breeze.Runtime.Hook{module: TaggedHook}] = :sys.get_state(pid).rendered.runtime_hooks

    stop_gen_server(pid)
  end

  test "hook contexts expose rows written by child patches" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    state_opts = []

    {:ok, pid} =
      start_app_server(
        view: ForkRoot,
        terminal: terminal,
        runtime_hooks: [{TaggedHook, owner: self(), id: :patch, state_opts: state_opts}]
      )

    assert_receive {:tagged_hook_init, :patch, %{view: ForkRoot}}
    assert_receive {:tagged_hook_event, :patch, 1, %{mode: :full}}

    assert_receive {:tagged_hook_capture, :patch, 1, :rendered, {:ok, _runtime_state}, _,
                    %{frame: _frame}}

    assert {:noreply, "child", true} = Breeze.Server.dispatch_live_input(pid, "child", "+")

    assert_receive {:tagged_hook_event, :patch, 2, %{mode: :patch, child_id: "child"}}

    assert_receive {:tagged_hook_capture, :patch, 2, :rendered, {:ok, _runtime_state}, _,
                    %{frame: frame}}

    assert Enum.all?(frame.lines, &is_binary/1)

    assert frame.lines |> Enum.join("\n") |> BackBreeze.Utils.strip_escape_chars() =~ "child=11"

    assert Enum.all?(:sys.get_state(pid).frame.last_lines, &is_binary/1)

    stop_gen_server(pid)
  end

  test "multiple runtime hooks keep independent state and capture lazily" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    state_opts = []

    {:ok, pid} =
      start_app_server(
        view: ForkRoot,
        terminal: terminal,
        runtime_hooks: [
          {TaggedHook, owner: self(), id: :first, every: 1, state_opts: state_opts},
          {TaggedHook, owner: self(), id: :second, every: 1, state_opts: state_opts}
        ]
      )

    assert_receive {:tagged_hook_init, :first, %{view: ForkRoot}}
    assert_receive {:tagged_hook_init, :second, %{view: ForkRoot}}
    assert_receive {:tagged_hook_event, :first, 1, %{mode: :full}}
    assert_receive {:tagged_hook_event, :second, 1, %{mode: :full}}

    assert_receive {:tagged_hook_capture, :first, 1, :rendered, {:ok, initial_state}, _, _}

    assert_receive {:tagged_hook_capture, :second, 1, :rendered, {:ok, ^initial_state}, _, _}

    assert Enum.map(:sys.get_state(pid).rendered.runtime_hooks, & &1.state.render_count) == [1, 1]

    send(pid, {terminal.reader, {:data, "+"}})

    wait_until(fn ->
      Enum.all?(
        :sys.get_state(pid).rendered.runtime_hooks,
        &(&1.state.render_count > 1)
      )
    end)

    activity = collect_hook_activity(pid, nil, 0)

    first_counts = hook_event_counts(activity, :first)
    second_counts = hook_event_counts(activity, :second)

    assert first_counts != []
    assert first_counts == second_counts
    assert length(activity.runtime_states) == length(first_counts) * 2

    Enum.each(first_counts, fn count ->
      assert {:ok, runtime_state} = hook_capture(activity, :first, count)
      assert {:ok, ^runtime_state} = hook_capture(activity, :second, count)
    end)

    assert Enum.map(:sys.get_state(pid).rendered.runtime_hooks, & &1.state.render_count) ==
             List.duplicate(List.last(first_counts), 2)

    stop_gen_server(pid)
  end

  @tag capture_log: true
  test "a failing runtime hook does not disable the others" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: ForkRoot,
        terminal: terminal,
        runtime_hooks: [
          {FailingHook, owner: self()},
          {TaggedHook, owner: self(), id: :healthy, every: 2}
        ]
      )

    assert_receive :failing_hook_called
    assert_receive {:tagged_hook_init, :healthy, %{view: ForkRoot}}
    assert_receive {:tagged_hook_event, :healthy, 1, %{mode: :full}}

    assert [%Breeze.Runtime.Hook{module: TaggedHook}] =
             :sys.get_state(pid).rendered.runtime_hooks

    send(pid, {terminal.reader, {:data, "+"}})

    assert_receive {:tagged_hook_event, :healthy, 2, %{mode: :full}}, 500

    assert_receive {:tagged_hook_capture, :healthy, 2, :rendered, {:ok, _runtime_state},
                    _metadata, _diagnostics},
                   500

    stop_gen_server(pid)
  end

  test "periodic animation notifications are opt-in per hook" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, quiet_pid} =
      start_app_server(
        view: AnimatedRoot,
        terminal: terminal,
        runtime_hooks: [{TaggedHook, owner: self(), id: :quiet}]
      )

    assert_receive {:tagged_hook_init, :quiet, %{view: AnimatedRoot}}
    assert_receive {:tagged_hook_event, :quiet, 1, %{mode: :full}}

    assert_receive {:tagged_hook_capture, :quiet, 1, :rendered, {:ok, _runtime_state}, _, _}

    quiet_state = :sys.get_state(quiet_pid)
    send(quiet_pid, {:animation_tick, quiet_state.frame.animation_generation})
    quiet_after_tick = :sys.get_state(quiet_pid)

    assert hd(quiet_after_tick.rendered.runtime_hooks).state.render_count == 1
    refute_received {:tagged_hook_event, :quiet, 2, _metadata}

    stop_gen_server(quiet_pid)

    {:ok, notified_pid} =
      start_app_server(
        view: AnimatedRoot,
        terminal: terminal,
        runtime_hooks: [
          {TaggedHook, owner: self(), id: :notified, notify_animation?: true}
        ]
      )

    assert_receive {:tagged_hook_init, :notified, %{view: AnimatedRoot}}
    assert_receive {:tagged_hook_event, :notified, 1, %{mode: :full}}

    assert_receive {:tagged_hook_capture, :notified, 1, :rendered, {:ok, _runtime_state}, _, _}

    notified_state = :sys.get_state(notified_pid)
    send(notified_pid, {:animation_tick, notified_state.frame.animation_generation})

    assert_receive {:tagged_hook_event, :notified, 2, %{mode: :animation, cause: :animation_tick}}

    assert_receive {:tagged_hook_capture, :notified, 2, :rendered, {:ok, _runtime_state},
                    %{mode: :animation}, _diagnostics}

    stop_gen_server(notified_pid)
  end
end
