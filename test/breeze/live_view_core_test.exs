defmodule Breeze.LiveView.CoreTest do
  use Breeze.TestSupport.LiveViewCase, async: true

  import Breeze.TestSupport.LiveViewHelpers

  test "render_to_tree preserves typed live attrs" do
    [{:box, _, [{:live, attrs}]}] =
      ParentLiveExample.render(%{start_opts: [seed: 1]})
      |> Template.render_to_tree(%{start_opts: [seed: 1]})

    assert attrs.id == "child"
    assert attrs.view == CounterChild
    assert attrs.start_opts == [seed: 1]
  end

  test "child server keeps its own state across events" do
    {:ok, pid} = start_child_server(view: CounterChild, start_opts: [])

    assert %{focused: "button", view: CounterChild} = ChildServer.metadata(pid)

    assert {:noreply, "button", true} =
             ChildServer.dispatch_event(pid, :input, %{"key" => "+"})

    {:ok, _acc, box} = ChildServer.render(pid, focused: "button", implicit_state: %{})
    assert box.content =~ "Count: 2"
  end

  test "child server dispatch_input advances focus and can clear it" do
    {:ok, pid} = start_child_server(view: CounterChild, start_opts: [])

    assert {:noreply, nil, true} = ChildServer.dispatch_input(pid, "\t")
    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})
    refute box.content =~ "\e[7m"
  end

  test "child server reports unhandled keys as unconsumed" do
    {:ok, pid} = start_child_server(view: CounterChild, start_opts: [])

    assert {:noreply, "button", false} = ChildServer.dispatch_input(pid, "x")
    assert {:noreply, "button", true} = ChildServer.dispatch_input(pid, "+")
  end

  test "child server render_snapshot exposes animate-capable implicit boxes" do
    {:ok, pid} = start_child_server(view: SpinnerChild, start_opts: [])

    assert {:ok, _acc, _box, [%{box: %BackBreeze.Box{}, every_ms: 120, id: "spinner"}]} =
             ChildServer.render_snapshot(pid, focused: nil, implicit_state: %{})
  end

  test "live child layout does not shift following sibling elements" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 10}}

    {:ok, pid} = start_child_server(view: LiveThenSiblingExample, terminal: terminal)

    assert {:ok, _acc, _box, _decorations} =
             ChildServer.render_snapshot(pid, terminal: terminal)

    elements = ChildServer.layout_snapshot(pid).elements

    assert %Breeze.Viewport{top: child_top, height: child_height} = elements["child"]
    assert %Breeze.Viewport{left: 0, top: after_top, width: 5, height: 1} = elements["after"]
    assert after_top == child_top + child_height
  end

  test "focused child keybindings are exposed to the parent footer assign" do
    {:ok, pid} = start_child_server(view: KeybindingFooterRoot, start_opts: [])

    terminal = %Termite.Terminal{size: %{width: 64, height: 6}}

    assert {:ok, _acc, box, _decorations} =
             ChildServer.render_snapshot(pid, implicit_state: %{}, terminal: terminal)

    assert box.content =~ "Esc"
    assert box.content =~ "Close"
    assert box.content =~ "Enter"
    assert box.content =~ "Save"
    assert %{active_keybindings: [%{key: "Esc"}, %{key: "Enter"}]} = ChildServer.metadata(pid)
  end

  test "renderer namespaces child ids and focusables" do
    {:ok, pid} = start_child_server(view: CounterChild, start_opts: [])

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

  test "renderer emits profiling telemetry events for external consumers" do
    handler_id = "breeze-live-view-test-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:breeze, :render, :stop],
          [:breeze, :render, :metric]
        ],
        &Breeze.LiveViewTest.telemetry_test_handler/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    profile_scope = make_ref()

    {_acc, box} =
      Renderer.render(CounterChild, %{count: 1},
        profile_scope: profile_scope,
        profile_label: "counter-child"
      )

    assert box.content =~ "Count: 1"

    assert_receive {:telemetry_event, [:breeze, :render, :stop], measurements,
                    %{scope: ^profile_scope} = metadata}

    assert is_integer(measurements.duration)
    assert metadata.label == "counter-child"
    assert metadata.metric in [:view_render_us, :template_tree_us, :build_tree_us, :layout_us]

    assert_receive {:telemetry_event, [:breeze, :render, :metric], %{value: value},
                    %{scope: ^profile_scope} = metadata}

    assert value > 0
    assert metadata.label == "counter-child"
    assert metadata.metric == :element_count

    Breeze.DebugProfiler.discard(profile_scope)
  end

  test "debug profiler snapshots telemetry-derived profiling metrics" do
    profile_scope = make_ref()
    Breeze.DebugProfiler.reset(profile_scope)

    {_acc, box} =
      Renderer.render(CounterChild, %{count: 1},
        profile_scope: profile_scope,
        profile_label: "counter-child"
      )

    assert box.content =~ "Count: 1"

    snapshot = Breeze.DebugProfiler.snapshot(profile_scope)

    assert Enum.any?(snapshot, fn entry ->
             entry.label == "counter-child" and entry.metric == :view_render_us and
               is_integer(entry.value) and entry.value >= 0
           end)

    assert Enum.any?(snapshot, fn entry ->
             entry.label == "counter-child" and entry.metric == :element_count and entry.value > 0
           end)

    assert Breeze.DebugProfiler.snapshot(profile_scope) == []
  end

  test "root child tab traverses namespaced live child focusables" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, left_pid} = start_child_server(view: CounterChild, start_opts: [], terminal: terminal)

    {:ok, right_pid} = start_child_server(view: CounterChild, start_opts: [], terminal: terminal)

    {:ok, root_pid} =
      start_child_server(view: DualLiveExample, start_opts: [], terminal: terminal)

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

  test "focusable live child keeps root focus when child has no local focus target" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, root_pid} = start_child_server(view: FocusableLiveRootExample, terminal: terminal)

    assert {:ok, _acc, box, _decorations} =
             ChildServer.render_snapshot(root_pid, terminal: terminal)

    assert box.content =~ "Root count: 0"
    assert %{focused: "child"} = ChildServer.metadata(root_pid)

    assert {:noreply, "child", true} = ChildServer.dispatch_input(root_pid, "+")
    assert {:noreply, "child", true} = ChildServer.dispatch_input(root_pid, "+")

    assert {:ok, _acc, box, _decorations} =
             ChildServer.render_snapshot(root_pid, terminal: terminal)

    assert box.content =~ "Root count: 2"
  end

  test "root child forwards mouse wheel input to a live child scroll implicit" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 10}}

    {:ok, root_pid} = start_child_server(view: MouseScrollLiveParent, terminal: terminal)

    assert {:ok, _acc, _box, _decorations} =
             ChildServer.render_snapshot(root_pid, terminal: terminal)

    %{children: %{"scroll-child" => %{pid: child_pid}}} = :sys.get_state(root_pid)
    targets = ChildServer.layout_snapshot(root_pid).mouse_targets

    assert {:noreply, "anchor", true} =
             ChildServer.dispatch_input(
               root_pid,
               wheel_event("wheel_down", targets["scroll-child::scroll"])
             )

    assert ChildServer.metadata(root_pid).focused == "anchor"

    assert {Breeze.Implicit.Scroll, %{offset_y: offset_y}} =
             ChildServer.metadata(child_pid).implicit_state["scroll"]

    assert offset_y > 0
  end

  test "server forwards mouse wheel input to a live child scroll implicit" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: MouseScrollLiveParent,
        terminal: terminal,
        mouse: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> stop_gen_server(pid) end)

    {child_pid, bounds} =
      wait_until(fn ->
        state = :sys.get_state(pid)
        targets = ChildServer.layout_snapshot(state.view_pid).mouse_targets

        with %{pid: child_pid} <- state.children["scroll-child"],
             bounds when is_map(bounds) <- targets["scroll-child::scroll"] do
          {child_pid, bounds}
        else
          _ -> nil
        end
      end)

    {x, y} = mouse_center(bounds)
    send(pid, {reader, {:data, "\e[<65;#{x + 1};#{y + 1}M"}})

    offset_y =
      wait_until(fn ->
        case ChildServer.metadata(child_pid).implicit_state["scroll"] do
          {Breeze.Implicit.Scroll, %{offset_y: offset_y}} when offset_y > 0 -> offset_y
          _ -> nil
        end
      end)

    assert offset_y > 0
  end

  test "theme changes cascade to nested live children immediately" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    {:ok, pid} =
      start_child_server(
        view: ThemeSwitchingParent,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:gruvbox)
      )

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)

    branch = :sys.get_state(pid).children["branch"].pid
    leaf = :sys.get_state(branch).children["leaf"].pid

    assert ChildServer.metadata(pid).theme.name == "gruvbox-dark"
    assert ChildServer.metadata(branch).theme.name == "gruvbox-dark"
    assert ChildServer.metadata(leaf).theme.name == "gruvbox-dark"

    assert {:noreply, "switch", true} = ChildServer.dispatch_event(pid, "switch", %{"key" => "t"})

    assert ChildServer.metadata(pid).theme.name == "nebula"
    assert ChildServer.metadata(branch).theme.name == "nebula"
    assert ChildServer.metadata(leaf).theme.name == "nebula"
  end

  test "server preserves mounted theme defaults for live children across theme changes" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: Breeze.LiveViewTest.MountedThemeLiveParent,
        terminal: terminal
      )

    on_exit(fn -> stop_gen_server(pid) end)

    state = :sys.get_state(pid)
    child = state.children["themed-child"].pid

    assert state.theme.name == "gruvbox-dark"
    assert state.apply_theme_defaults?
    assert ChildServer.metadata(child).apply_theme_defaults?

    assert {:noreply, "switch", true} =
             ChildServer.dispatch_event(state.view_pid, "switch", %{"key" => "t"})

    wait_until(fn ->
      state = :sys.get_state(pid)
      child_metadata = ChildServer.metadata(child)

      state.theme.name == "nebula" and child_metadata.theme.name == "nebula"
    end)

    state = :sys.get_state(pid)

    assert state.apply_theme_defaults?
    assert ChildServer.metadata(child).apply_theme_defaults?
  end

  test "child server stops nested live children when it terminates" do
    {:ok, pid} = start_child_server(view: ThemeSwitchingParent, start_opts: [])

    assert {:ok, _acc, _box} = ChildServer.render(pid, [])

    branch = :sys.get_state(pid).children["branch"].pid
    leaf = :sys.get_state(branch).children["leaf"].pid
    branch_ref = Process.monitor(branch)
    leaf_ref = Process.monitor(leaf)

    GenServer.stop(pid, :normal)

    assert_receive {:DOWN, ^branch_ref, :process, ^branch, _reason}, 500
    assert_receive {:DOWN, ^leaf_ref, :process, ^leaf, _reason}, 500
    refute Process.alive?(branch)
    refute Process.alive?(leaf)
  end

  test "child server stops inactive non-persistent live children" do
    {:ok, pid} = start_child_server(view: DebugToggleRoot, start_opts: [])

    assert {:ok, _acc, _box} = ChildServer.render(pid, [])

    assert {:noreply, _, true} = ChildServer.dispatch_input(pid, "F2")
    assert {:ok, _acc, _box} = ChildServer.render(pid, [])
    child = :sys.get_state(pid).children["debug"].pid

    assert {:noreply, _, true} = ChildServer.dispatch_input(pid, "F2")
    assert {:ok, _acc, _box} = ChildServer.render(pid, [])

    refute Map.has_key?(:sys.get_state(pid).children, "debug")
    refute Process.alive?(child)

    GenServer.stop(pid, :normal)
  end

  test "child server retains inactive persistent live children" do
    {:ok, pid} = start_child_server(view: PersistentToggleRoot, start_opts: [])

    assert {:ok, _acc, _box} = ChildServer.render(pid, [])
    child = :sys.get_state(pid).children["persistent"].pid

    assert {:noreply, _, true} = ChildServer.dispatch_event(pid, "toggle", %{})
    assert {:ok, _acc, _box} = ChildServer.render(pid, [])

    assert :sys.get_state(pid).children["persistent"].pid == child
    assert Process.alive?(child)

    assert {:noreply, _, true} = ChildServer.dispatch_event(pid, "toggle", %{})
    assert {:ok, _acc, _box} = ChildServer.render(pid, [])
    assert :sys.get_state(pid).children["persistent"].pid == child

    GenServer.stop(pid, :normal)
    refute Process.alive?(child)
  end

  test "unfocused live children do not render their own local focus ring" do
    {:ok, pid} = start_child_server(view: FocusedChild, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})

    refute box.content =~ "\e[7m"
  end

  test "child server emits invalidation on async state changes" do
    parent = self()

    {:ok, pid} =
      start_child_server(
        view: AnimatedChild,
        start_opts: [],
        invalidate: fn -> send(parent, :invalidate) end
      )

    assert_receive :invalidate

    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})
    assert box.content =~ "Frame: 1"
  end

  test "server reschedules animation when a faster decoration appears" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
        view: FasterDecorationRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> stop_gen_server(pid) end)

    initial_state = :sys.get_state(pid)
    assert Enum.any?(initial_state.frame.decorations, &(&1.id == "search"))
    assert is_reference(initial_state.frame.animation_timer)

    assert {:noreply, "search", true} =
             ChildServer.dispatch_event(initial_state.view_pid, "show_loading", %{})

    send(pid, :child_invalidated)

    assert wait_until(fn ->
             state = :sys.get_state(pid)

             Enum.find_value(state.frame.decorations, fn
               %{
                 id: "fast",
                 frame_index: frame_index,
                 current_overlays: [%{content: content} | _]
               }
               when frame_index > 0 ->
                 content

               _decoration ->
                 false
             end)
           end) in ["b", "c"]
  end

  test "server preserves private-use glyphs in terminal output" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      start_app_server(
        view: PrivateUseGlyphRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> stop_gen_server(pid) end)

    payload =
      wait_until(fn ->
        writes = drain_terminal_writes()

        if Enum.any?(writes, &String.contains?(&1, "")) do
          IO.iodata_to_binary(writes)
        end
      end)

    assert payload =~ " _build"
    assert payload =~ "󰂺 README.md"
  end

  test "server starts nested live children that appear after an event" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: DebugToggleRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOQ"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      Map.has_key?(state.children, "debug") and state.frame.base_output =~ "Count: 1"
    end)

    state = :sys.get_state(pid)
    assert Map.has_key?(state.children, "debug")
    assert state.frame.base_output =~ "Count: 1"

    stop_gen_server(pid)
  end

  test "server stops inactive non-persistent live children" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = start_app_server(view: DebugToggleRoot, terminal: terminal)

    send(pid, {reader, {:data, "\eOQ"}})

    child =
      wait_until(fn ->
        case :sys.get_state(pid).children["debug"] do
          %{pid: child} -> child
          _ -> nil
        end
      end)

    send(pid, {reader, {:data, "\eOQ"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      not Map.has_key?(state.children, "debug")
    end)

    refute Process.alive?(child)
    GenServer.stop(pid, :normal)
  end

  test "server stops its root view and live children when it terminates" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: FocusableLiveRootExample, terminal: terminal)

    state = :sys.get_state(pid)
    root = state.view_pid
    child = state.children["child"].pid

    Process.unlink(pid)

    capture_log(fn ->
      Process.exit(pid, :kill)
      wait_until(fn -> not Process.alive?(root) and not Process.alive?(child) end)
    end)
  end

  test "server can snapshot and dispatch input to a live child by id" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      start_app_server(
        view: FocusableLiveRootExample,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    assert {:ok, snapshot} = Breeze.Server.live_snapshot(pid, "child")
    assert snapshot.content =~ "Root count: 0"

    ref = make_ref()
    Breeze.Server.request_live_snapshot(pid, "child", self(), ref)
    assert_receive {:breeze_live_snapshot, ^ref, "child", {:ok, async_snapshot}}, 500
    assert async_snapshot.content =~ "Root count: 0"

    assert {:noreply, "child", true} = Breeze.Server.dispatch_live_input(pid, "child", "+")

    assert {:ok, snapshot} = Breeze.Server.live_snapshot(pid, "child")
    assert snapshot.content =~ "Root count: 1"

    stop_gen_server(pid)
  end

  test "live snapshot settles a deferred root render before resolving the child" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} = start_app_server(view: SwitchableLiveRoot, terminal: terminal)
    previous_child = :sys.get_state(pid).children["preview"].pid

    :sys.replace_state(pid, fn state ->
      put_in(state.frame.last_render_at, System.monotonic_time(:millisecond) + 5_000)
    end)

    send(pid, {terminal.reader, {:data, "s"}})

    wait_until(fn ->
      state = :sys.get_state(pid)

      Breeze.ChildServer.metadata(state.view_pid).assigns.child_view == AlternateChild and
        is_nil(state.input.pending_ref) and state.input.render_after_flush?
    end)

    assert {:ok, snapshot} = Breeze.Server.live_snapshot(pid, "preview")
    assert snapshot.content =~ "Alternate child"

    state = :sys.get_state(pid)
    assert state.children["preview"].view == AlternateChild
    refute Process.alive?(previous_child)

    stop_gen_server(pid)
  end

  test "live snapshot call adopts crash state when child render crashes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} = start_app_server(view: SnapshotCrashingRoot, terminal: terminal)

      assert {:ok, snapshot} = Breeze.Server.live_snapshot(pid, "child")
      assert snapshot.content =~ "snapshot ready"

      assert {:noreply, _focused, false} = Breeze.Server.dispatch_live_input(pid, "child", "c")
      assert {:crash, crash} = Breeze.Server.live_snapshot(pid, "child")
      assert %RuntimeError{message: "snapshot boom"} = crash.reason

      state = :sys.get_state(pid)
      assert state.crash
      assert state.crash.reason == crash.reason
      assert state.frame.base_output =~ "Breeze Error"
      assert state.frame.base_output =~ "snapshot boom"

      stop_gen_server(pid)
    end)
  end

  test "requested live snapshot adopts crash state when child render crashes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} = start_app_server(view: SnapshotCrashingRoot, terminal: terminal)

      assert {:noreply, _focused, false} = Breeze.Server.dispatch_live_input(pid, "child", "c")

      ref = make_ref()
      Breeze.Server.request_live_snapshot(pid, "child", self(), ref)
      assert_receive {:breeze_live_snapshot, ^ref, "child", {:crash, crash}}, 500
      assert %RuntimeError{message: "snapshot boom"} = crash.reason

      state = :sys.get_state(pid)
      assert state.crash
      assert state.crash.reason == crash.reason
      assert state.frame.base_output =~ "Breeze Error"
      assert state.frame.base_output =~ "snapshot boom"

      stop_gen_server(pid)
    end)
  end

  test "server updates live child assigns in place when dynamic assigns change" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      start_app_server(
        view: LiveAssignsRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.frame.base_output =~ "muted"
    end)

    child_before = :sys.get_state(pid).children["preview"]
    assert child_before.assigns == %{variant: "muted"}

    send(pid, {reader, {:data, "v"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.frame.base_output =~ "accent"
    end)

    child_after = :sys.get_state(pid).children["preview"]
    assert child_after.assigns == %{variant: "accent"}
    assert child_after.pid == child_before.pid

    stop_gen_server(pid)
  end

  test "server preserves repeated identical key events in the input queue" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} = start_app_server(view: BufferedScrollView, terminal: terminal)

    Enum.each(1..5, fn _ -> send(pid, {reader, {:data, "\e[6~"}}) end)

    wait_until(fn ->
      state = :sys.get_state(pid)

      not state.input.flush_scheduled? and is_nil(state.input.render_timer) and
        :queue.is_empty(state.input.queued_input)
    end)

    %{view_pid: view_pid} = :sys.get_state(pid)

    assert %{implicit_state: %{"scroll" => {Breeze.Implicit.Scroll, scroll_state}}} =
             Breeze.ChildServer.metadata(view_pid)

    assert scroll_state.offset_y == 115

    stop_gen_server(pid)
  end
end
