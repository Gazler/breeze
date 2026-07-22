defmodule Breeze.RuntimeTest do
  use ExUnit.Case, async: false

  import Breeze.TestSupport.WaitUntil

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {width, height} = Keyword.get(opts, :size, {80, 24})
      {:ok, %{ref: make_ref(), size: %{width: width, height: height}}}
    end

    def reader(terminal), do: {:ok, terminal.ref}
    def write(terminal, _content), do: {:ok, terminal}
    def resize(terminal), do: terminal.size
  end

  defmodule RecordingAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {width, height} = Keyword.get(opts, :size, {80, 24})

      {:ok,
       %{
         ref: make_ref(),
         size: %{width: width, height: height},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(terminal), do: {:ok, terminal.ref}

    def write(terminal, content) do
      send(terminal.owner, {:terminal_write, content})
      {:ok, terminal}
    end

    def resize(terminal), do: terminal.size
  end

  defmodule StatefulImplicit do
    def init(_children, _attrs, state), do: {:ok, Map.put_new(state, :count, 0)}

    def handle_event(_, %{"key" => "i"}, state) do
      {:noreply, %{state | count: state.count + 1}}
    end

    def handle_event(_, _, state), do: {:noreply, state}
    def handle_modifiers(_, _, _state), do: []
  end

  defmodule ForkChild do
    use Breeze.View

    def mount(opts, term) do
      {:ok, term |> assign(count: Keyword.get(opts, :count, 0)) |> focus("child-button")}
    end

    def render(assigns) do
      ~H"""
      <box id="child-button" focusable>child={@count}</box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, %{"key" => "-"}, term) do
      {:noreply, assign(term, count: term.assigns.count - 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule ForkRoot do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(count: 0) |> focus("root")}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box id="root" focusable implicit={StatefulImplicit}>root={@count}</box>
        <live id="child" view={ForkChild} start_opts={[count: 10]} focusable>
        </live>
      </box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, %{"key" => "-"}, term) do
      {:noreply, assign(term, count: term.assigns.count - 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule PersistentRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, show_child: true)}

    def render(assigns) do
      ~H"""
      <box>
        <live
          :if={@show_child}
          id="persistent"
          view={ForkChild}
          start_opts={[count: 10]}
          persistent={true}
        >
        </live>
      </box>
      """
    end

    def handle_event(:toggle, _event, term) do
      {:noreply, assign(term, show_child: !term.assigns.show_child)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule CaptureHook do
    @behaviour Breeze.Runtime.Hook

    def init(opts, metadata) do
      send(Keyword.fetch!(opts, :owner), {:hook_init, metadata})

      %{
        owner: Keyword.fetch!(opts, :owner),
        every: Keyword.get(opts, :every, 1),
        render_count: 0
      }
    end

    def handle_event(:rendered, context, state) do
      metadata = Breeze.Runtime.Context.metadata(context)
      state = %{state | render_count: state.render_count + 1}
      send(state.owner, {:hook_event, state.render_count, metadata})

      if rem(state.render_count, state.every) == 0 do
        send(
          state.owner,
          {:hook_capture, :rendered, Breeze.Runtime.Context.capture_state(context), metadata,
           %{
             frame: Breeze.Runtime.Context.frame(context),
             inspector: Breeze.Runtime.Context.inspector(context)
           }}
        )
      end

      {:noreply, state}
    end
  end

  defmodule TaggedHook do
    @behaviour Breeze.Runtime.Hook

    def init(opts, metadata) do
      state = %{
        owner: Keyword.fetch!(opts, :owner),
        id: Keyword.fetch!(opts, :id),
        every: Keyword.get(opts, :every, 1),
        state_opts: Keyword.get(opts, :state_opts, []),
        render_count: 0
      }

      send(state.owner, {:tagged_hook_init, state.id, metadata})
      state
    end

    def handle_event(:rendered, context, state) do
      metadata = Breeze.Runtime.Context.metadata(context)
      state = %{state | render_count: state.render_count + 1}
      send(state.owner, {:tagged_hook_event, state.id, state.render_count, metadata})

      if rem(state.render_count, state.every) == 0 do
        send(
          state.owner,
          {:tagged_hook_capture, state.id, state.render_count, :rendered,
           Breeze.Runtime.Context.capture_state(context, state.state_opts), metadata,
           %{frame: Breeze.Runtime.Context.frame(context)}}
        )
      end

      {:noreply, state}
    end
  end

  defmodule HookPage do
    use Breeze.RemoteInspector.Page

    def page(opts) do
      [
        label: "Runtime hook",
        runtime_hooks: [{Breeze.RuntimeTest.TaggedHook, opts}]
      ]
    end

    def render(assigns), do: ~H"<box>Runtime hook</box>"
  end

  defmodule FailingHook do
    @behaviour Breeze.Runtime.Hook

    def init(opts, _metadata), do: Keyword.fetch!(opts, :owner)

    def handle_event(:rendered, _context, owner) do
      send(owner, :failing_hook_called)
      raise "hook failed"
    end
  end

  defmodule MountSideEffectView do
    use Breeze.View

    def mount(opts, term) do
      send(Keyword.fetch!(opts, :owner), {:mounted, self()})
      {:ok, assign(term, count: 7)}
    end

    def render(assigns) do
      ~H"""
      <box>count={@count}</box>
      """
    end
  end

  defmodule BlockingView do
    use Breeze.View

    def mount(opts, term), do: {:ok, assign(term, owner: Keyword.fetch!(opts, :owner))}

    def render(assigns) do
      ~H"""
      <box>blocking</box>
      """
    end

    def handle_info({:block, owner}, term) do
      send(owner, {:view_blocked, self()})

      receive do
        :unblock -> {:noreply, term}
      end
    end

    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule AnimatedImplicit do
    def init(_children, _attrs, state), do: {:ok, state, rerender_every: 10_000}
    def handle_modifiers(_, _, _state), do: []

    def animate(:root, box, _flags, _state, %{frame: frame}) do
      %{box | content: "frame=#{frame}"}
    end

    def animate(:child, box, _flags, _state, _ctx), do: box
  end

  defmodule AnimatedRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="animated" implicit={AnimatedImplicit}>frame</box>
      """
    end
  end

  defmodule FocusChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, focus(term, "first")}

    def render(assigns) do
      ~H"""
      <box>
        <box id="first" focusable>first</box>
        <box id="second" focusable>second</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "x"}, term), do: {:noreply, focus(term, "second")}
    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule FocusRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, focus(term, "root")}

    def render(assigns) do
      ~H"""
      <box>
        <box id="root" focusable>root</box>
        <live id="child" view={FocusChild} focusable>
        </live>
      </box>
      """
    end
  end

  defmodule NestedPersistentLeaf do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0)}

    def render(assigns) do
      ~H"""
      <box>nested={@count}</box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule NestedPersistentParent do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box>
        <live id="leaf" view={NestedPersistentLeaf} persistent={true}>
        </live>
      </box>
      """
    end
  end

  defmodule NestedPersistentRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, show_parent: true)}

    def render(assigns) do
      ~H"""
      <box>
        <live :if={@show_parent} id="parent" view={NestedPersistentParent}>
        </live>
      </box>
      """
    end

    def handle_event(:toggle_parent, _event, term) do
      {:noreply, assign(term, show_parent: !term.assigns.show_parent)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule RestoreChildrenRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box>
        <live id="a" view={ForkChild}>
        </live>
        <live id="b" view={ForkChild}>
        </live>
      </box>
      """
    end
  end

  test "runtime capture stays disabled unless an hook is configured" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: ForkRoot,
        terminal: terminal
      )

    assert :sys.get_state(pid).rendered.runtime_hooks == []
    refute_receive {:hook_event, _, _}, 50

    capture_mfa = {Breeze.Runtime.State, :capture_server, 2}
    :erlang.trace_pattern(capture_mfa, true, [:local])
    :erlang.trace(pid, true, [:call])

    try do
      send(pid, {reader, {:data, "+"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        Breeze.ChildServer.metadata(state.view_pid).assigns.count == 1
      end)

      refute_receive {:trace, ^pid, :call, {Breeze.Runtime.State, :capture_server, _arguments}},
                     50
    after
      :erlang.trace(pid, false, [:call])
      :erlang.trace_pattern(capture_mfa, false, [:local])
    end

    Process.exit(pid, :normal)
  end

  test "a captured frame can be displayed in the source application and restored" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = Breeze.Server.start_app_link(view: ForkRoot, terminal: terminal)

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

    Process.exit(pid, :normal)
  end

  test "a timed out suspension is still resumed when returning to the live frame" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: BlockingView,
        start_opts: [owner: self()],
        terminal: terminal
      )

    view_pid = :sys.get_state(pid).view_pid
    send(view_pid, {:block, self()})
    assert_receive {:view_blocked, ^view_pid}

    assert :ok = Breeze.Runtime.display_frame(pid, %{lines: ["paused"]})
    assert view_pid in :sys.get_state(pid).frame.display_suspended_pids

    send(view_pid, :unblock)
    assert :ok = Breeze.Runtime.display_frame(pid, :live)
    assert %{view: BlockingView} = Breeze.ChildServer.metadata(view_pid)

    Process.exit(pid, :normal)
  end

  test "historical frames replay overlays and fit captured rows to the current width" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self(), size: {4, 2})
    {:ok, pid} = Breeze.Server.start_app_link(view: ForkRoot, terminal: terminal)

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

    Process.exit(pid, :normal)
  end

  test "runtime state can replace the source runtime and resume on the next input" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = Breeze.Server.start_app_link(view: ForkRoot, terminal: terminal)

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

    Process.exit(pid, :normal)
  end

  test "configured hooks lazily capture runtime state and diagnostics" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: ForkRoot,
        terminal: terminal,
        inspector: true,
        runtime_hooks: [{CaptureHook, owner: self(), every: 2}]
      )

    assert_receive {:hook_init, %{view: ForkRoot}}
    assert_receive {:hook_event, 1, %{cause: :unknown, mode: :full}}
    refute_receive {:hook_capture, _, _, _, _}, 50

    reader = terminal.reader
    send(pid, {reader, {:data, "+"}})

    assert_receive {:hook_event, 2, %{mode: :full}}, 500

    assert_receive {:hook_capture, :rendered, {:ok, runtime_state}, metadata, diagnostics}, 500

    assert metadata.server_pid == pid
    assert runtime_state.view == ForkRoot
    assert is_list(diagnostics.frame.lines)
    assert diagnostics.inspector.enabled?

    assert %{state: %{term: %Breeze.Term{view: ForkChild}}} = runtime_state.root.children["child"]

    Process.exit(pid, :normal)
  end

  test "configured inspector pages contribute runtime hooks" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    Process.exit(pid, :normal)
  end

  test "hook contexts expose rows written by child patches" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    state_opts = []

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    Process.exit(pid, :normal)
  end

  test "multiple runtime hooks keep independent state and capture lazily" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    state_opts = []

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    capture_mfa = {Breeze.Runtime.State, :capture_server, 2}
    :erlang.trace_pattern(capture_mfa, true, [:local])
    :erlang.trace(pid, true, [:call])

    try do
      send(pid, {terminal.reader, {:data, "+"}})

      activity = collect_hook_activity(pid)

      first_counts = hook_event_counts(activity, :first)
      second_counts = hook_event_counts(activity, :second)

      assert first_counts != []
      assert first_counts == second_counts
      assert activity.capture_count == length(first_counts) * 2

      Enum.each(first_counts, fn count ->
        assert {:ok, runtime_state} = hook_capture(activity, :first, count)
        assert {:ok, ^runtime_state} = hook_capture(activity, :second, count)
      end)

      assert Enum.map(:sys.get_state(pid).rendered.runtime_hooks, & &1.state.render_count) ==
               List.duplicate(List.last(first_counts), 2)
    after
      :erlang.trace(pid, false, [:call])
      :erlang.trace_pattern(capture_mfa, false, [:local])
    end

    Process.exit(pid, :normal)
  end

  @tag capture_log: true
  test "a failing runtime hook does not disable the others" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    Process.exit(pid, :normal)
  end

  test "periodic animation notifications are opt-in per hook" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, quiet_pid} =
      Breeze.Server.start_app_link(
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
    refute_receive {:tagged_hook_event, :quiet, 2, _metadata}, 50

    Process.exit(quiet_pid, :normal)

    {:ok, notified_pid} =
      Breeze.Server.start_app_link(
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

    Process.exit(notified_pid, :normal)
  end

  test "state replacement cancels and isolates the previous animation timer" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = Breeze.Server.start_app_link(view: AnimatedRoot, terminal: terminal)
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

    Process.exit(pid, :normal)
  end

  test "runtime state preserves implicit and nested live state in isolated runtimes" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = Breeze.Server.start_app_link(view: ForkRoot, terminal: terminal, inspector: true)

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

    Process.exit(pid, :normal)
  end

  test "state replacement preserves the server-level live focus path" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = Breeze.Server.start_app_link(view: FocusRoot, terminal: terminal)

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

    Process.exit(pid, :normal)
  end

  test "hidden persistent children survive replacement and isolated startup" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = Breeze.Server.start_app_link(view: PersistentRoot, terminal: terminal)

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

    Process.exit(pid, :normal)
  end

  test "persistent nested children can be captured while their parent is hidden" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: NestedPersistentRoot,
        terminal: terminal
      )

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

    Process.exit(pid, :normal)
  end

  test "replacement errors clean up the root and children started before the failure" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = Breeze.Server.start_app_link(view: RestoreChildrenRoot, terminal: terminal)
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

    Process.exit(pid, :normal)
  end

  test "isolated runtime theme overrides apply to restored descendants" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: ForkRoot,
        terminal: terminal
      )

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

    Process.exit(pid, :normal)
  end

  test "starting from runtime state does not rerun mount side effects" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: MountSideEffectView,
        start_opts: [owner: self()],
        terminal: terminal
      )

    assert_receive {:mounted, source_view_pid}
    assert is_pid(source_view_pid)

    assert {:ok, runtime_state} = Breeze.Runtime.capture_state(pid)
    assert {:ok, fork} = Breeze.Runtime.start_from_state(runtime_state)
    on_exit(fn -> Breeze.Runtime.stop(fork) end)

    refute_receive {:mounted, _fork_view_pid}, 100
    assert {:ok, snapshot} = Breeze.Runtime.snapshot(fork)
    assert snapshot.content =~ "count=7"

    Process.exit(pid, :normal)
  end

  defp collect_hook_activity(pid, activity \\ nil, timeout \\ 500) do
    activity =
      activity ||
        %{
          capture_count: 0,
          events: [],
          runtime_states: []
        }

    receive do
      {:trace, ^pid, :call, {Breeze.Runtime.State, :capture_server, _arguments}} ->
        collect_hook_activity(
          pid,
          %{activity | capture_count: activity.capture_count + 1},
          50
        )

      {:tagged_hook_event, id, count, metadata} ->
        collect_hook_activity(
          pid,
          %{activity | events: [{id, count, metadata} | activity.events]},
          50
        )

      {:tagged_hook_capture, id, count, :rendered, result, metadata, diagnostics} ->
        collect_hook_activity(
          pid,
          %{
            activity
            | runtime_states: [
                {id, count, result, metadata, diagnostics} | activity.runtime_states
              ]
          },
          50
        )
    after
      timeout -> activity
    end
  end

  defp hook_event_counts(activity, id) do
    activity.events
    |> Enum.filter(fn {event_id, _count, _metadata} -> event_id == id end)
    |> Enum.map(fn {_event_id, count, _metadata} -> count end)
    |> Enum.sort()
  end

  defp hook_capture(activity, id, count) do
    Enum.find_value(activity.runtime_states, :error, fn
      {^id, ^count, result, _metadata, _diagnostics} -> result
      _capture -> false
    end)
  end

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, content} -> drain_terminal_writes([content | writes])
    after
      10 -> Enum.reverse(writes)
    end
  end
end
