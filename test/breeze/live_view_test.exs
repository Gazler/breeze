defmodule Breeze.LiveViewTest do
  use ExUnit.Case, async: true

  alias Breeze.ChildServer
  alias Breeze.Renderer
  alias Breeze.Template
  import ExUnit.CaptureLog

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
       %{
         ref: make_ref(),
         size: %{width: 80, height: 24},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(term), do: {:ok, term.ref}

    def write(term, str) do
      send(term.owner, {:terminal_write, str})
      {:ok, term}
    end

    def resize(term), do: term.size
  end

  defmodule FakeWatcher do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def subscribe(pid) do
      GenServer.call(pid, {:subscribe, self()})
    end

    def trigger(pid, path, events \\ [:modified]) do
      GenServer.call(pid, {:trigger, path, events})
    end

    @impl true
    def init(opts) do
      {:ok, %{dirs: Keyword.fetch!(opts, :dirs), subscriber: nil}}
    end

    @impl true
    def handle_call({:subscribe, subscriber}, _from, state) do
      {:reply, :ok, %{state | subscriber: subscriber}}
    end

    def handle_call({:trigger, path, events}, _from, %{subscriber: subscriber} = state) do
      send(subscriber, {:file_event, self(), {path, events}})
      {:reply, :ok, state}
    end
  end

  defmodule CounterChild do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(count: 1) |> focus("button")}
    end

    def render(assigns) do
      ~H"""
      <box id="panel" style="border">
        <box id="button" focusable>Count: {@count}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule ParentLiveExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={CounterChild} start_opts={@start_opts}>
        </live>
      </box>
      """
    end
  end

  defmodule AnimatedChild do
    use Breeze.View

    def mount(_opts, term) do
      send(self(), :tick)
      {:ok, assign(term, frame: 0)}
    end

    def render(assigns) do
      ~H"""
      <box id="panel">Frame: {@frame}</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}

    def handle_info(:tick, term) do
      {:noreply, assign(term, frame: term.assigns.frame + 1)}
    end

    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule FocusedChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="button" focusable style="focus:inverse">Focusable</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule SpinnerChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="spinner" implicit={Breeze.Implicit.AsyncSpinner} style="width-1">
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule CrashingView do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(label: "ready") |> focus("boom")}
    end

    def render(assigns) do
      ~H"""
      <box id="boom" focusable>{@label}</box>
      """
    end

    def handle_event(_, %{"key" => "c"}, _term) do
      raise "boom"
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule DebugToggleRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, show_debug: false)}

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box>root</box>
        <box :if={@show_debug} style="fixed right-0 bottom-0 width-18 height-6">
          <live id="debug" view={CounterChild} start_opts={[]}>
          </live>
        </box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "F2"}, term) do
      {:noreply, assign(term, show_debug: !term.assigns.show_debug)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule DecoratedDebugChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 1)}

    def render(assigns) do
      ~H"""
      <box>
        <box id="spinner" implicit={Breeze.Implicit.AsyncSpinner} style="width-1">
        </box>
        <box id="button" focusable>Count: {@count}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule DecoratedDebugRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="fixed right-0 bottom-0 width-18 height-6">
          <live id="debug" view={DecoratedDebugChild} start_opts={[]}>
          </live>
        </box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule ReloadableView do
    use Breeze.View

    def mount(opts, term) do
      send(Keyword.fetch!(opts, :parent), :reloadable_view_mounted)
      {:ok, term |> assign(label: "ready") |> focus("root")}
    end

    def render(assigns) do
      ~H"""
      <box id="root" focusable>{@label}</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule ReloadConfigView do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(count: 0) |> focus("root")}
    end

    def render(assigns) do
      ~H"""
      <box id="root" focusable>Count: {@count}</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule NestedReloadLeaf do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H'<box id="leaf" focusable>leaf</box>'
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule NestedReloadChild do
    use Breeze.View
    import Breeze.Router

    def mount(_opts, term) do
      {:ok,
       term
       |> Breeze.Router.init([inner: NestedReloadLeaf], current: :inner)
       |> focus("child")}
    end

    def render(assigns) do
      ~H"""
      <box id="child" focusable>
        <.router routes={@router} id="nested"/>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule RootReloadWithNestedRouter do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(count: 0) |> focus("nested:child")}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box id="root" focusable>Count: {@count}</box>
        <live id="nested" view={NestedReloadChild} start_opts={[]}>
        </live>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  def telemetry_test_handler(event, measurements, metadata, parent) do
    send(parent, {:telemetry_event, event, measurements, metadata})
  end

  test "render_to_tree preserves typed live attrs" do
    [{:box, _, [{:live, attrs}]}] =
      ParentLiveExample.render(%{start_opts: [seed: 1]})
      |> Template.render_to_tree(%{start_opts: [seed: 1]})

    assert attrs.id == "child"
    assert attrs.view == CounterChild
    assert attrs.start_opts == [seed: 1]
  end

  test "child server keeps its own state across events" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

    assert %{focused: "button", view: CounterChild} = ChildServer.metadata(pid)

    assert {:noreply, "button", true} =
             ChildServer.dispatch_event(pid, :ignore_me, %{"key" => "+"})

    {:ok, _acc, box} = ChildServer.render(pid, focused: "button", implicit_state: %{})
    assert box.content =~ "Count: 2"
  end

  test "child server dispatch_input advances focus and can clear it" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

    assert {:noreply, nil, true} = ChildServer.dispatch_input(pid, "\t")
    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})
    refute box.content =~ "\e[7m"
  end

  test "child server reports unhandled keys as unconsumed" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

    assert {:noreply, "button", false} = ChildServer.dispatch_input(pid, "x")
    assert {:noreply, "button", true} = ChildServer.dispatch_input(pid, "+")
  end

  test "child server render_snapshot exposes animate-capable implicit boxes" do
    {:ok, pid} = ChildServer.start(view: SpinnerChild, start_opts: [])

    assert {:ok, _acc, _box, [%{box: %BackBreeze.Box{}, every_ms: 120, id: "spinner"}]} =
             ChildServer.render_snapshot(pid, focused: nil, implicit_state: %{})
  end

  test "renderer namespaces child ids and focusables" do
    {:ok, pid} = ChildServer.start(view: CounterChild, start_opts: [])

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
        &__MODULE__.telemetry_test_handler/4,
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

    assert_receive {:telemetry_event, [:breeze, :render, :stop], measurements, metadata}
    assert is_integer(measurements.duration)
    assert metadata.scope == profile_scope
    assert metadata.label == "counter-child"
    assert metadata.metric in [:view_render_us, :template_tree_us, :build_tree_us, :layout_us]

    assert_receive {:telemetry_event, [:breeze, :render, :metric], %{value: value}, metadata}
    assert value > 0
    assert metadata.scope == profile_scope
    assert metadata.label == "counter-child"
    assert metadata.metric == :element_count
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
  end

  defmodule DualLiveExample do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box>
        <live id="left" view={CounterChild} start_opts={[]}>
        </live>
        <live id="right" view={CounterChild} start_opts={[]}>
        </live>
      </box>
      """
    end
  end

  test "root child tab traverses namespaced live child focusables" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, left_pid} = ChildServer.start(view: CounterChild, start_opts: [], terminal: terminal)
    {:ok, right_pid} = ChildServer.start(view: CounterChild, start_opts: [], terminal: terminal)
    {:ok, root_pid} = ChildServer.start(view: DualLiveExample, start_opts: [], terminal: terminal)

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

  test "unfocused live children do not render their own local focus ring" do
    {:ok, pid} = ChildServer.start(view: FocusedChild, start_opts: [])

    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})

    refute box.content =~ "\e[7m"
  end

  test "child server emits invalidation on async state changes" do
    parent = self()

    {:ok, pid} =
      ChildServer.start(
        view: AnimatedChild,
        start_opts: [],
        invalidate: fn -> send(parent, :invalidate) end
      )

    assert_receive :invalidate

    {:ok, _acc, box} = ChildServer.render(pid, focused: nil, implicit_state: %{})
    assert box.content =~ "Frame: 1"
  end

  test "server starts nested live children that appear after an event" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: DebugToggleRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    send(pid, {reader, {:data, "\eOQ"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      Map.has_key?(state.children, "debug") and state.base_output =~ "Count: 1"
    end)

    state = :sys.get_state(pid)
    assert Map.has_key?(state.children, "debug")
    assert state.base_output =~ "Count: 1"

    Process.exit(pid, :normal)
  end

  test "server renders a crash screen instead of tearing down the terminal on view exceptions" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.base_output =~ "Breeze Error" &&
          state.base_output =~ "CrashingView" &&
          state.base_output =~ "RuntimeError"
      end)

      state = :sys.get_state(pid)

      assert state.crash
      assert state.base_output =~ "Breeze Error"
      assert state.base_output =~ "CrashingView"
      assert state.base_output =~ "RuntimeError"
      assert state.base_output =~ "Crash Details"
      assert state.base_output =~ "Selected Frame"
      assert state.base_output =~ "Stacktrace"
      assert state.base_output =~ "boom"

      Process.exit(pid, :normal)
    end)
  end

  test "crash screen tab switches focus between panes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.crash.focused == "error-stacktrace"
      end)

      initial_state = :sys.get_state(pid)
      assert initial_state.crash
      assert initial_state.crash.focused == "error-stacktrace"

      send(pid, {reader, {:data, "\t"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.crash.focused == "error-history"
      end)

      next_state = :sys.get_state(pid)
      assert next_state.crash.focused == "error-history"

      Process.exit(pid, :normal)
    end)
  end

  test "server restarts from a clean slate after a crash when r is pressed" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        not is_nil(state.crash)
      end)

      crashed_state = :sys.get_state(pid)
      assert crashed_state.crash

      send(pid, {reader, {:data, "r"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        is_nil(state.crash) and state.base_output =~ "ready" and
          not String.contains?(state.base_output, "Breeze Error")
      end)

      restarted_state = :sys.get_state(pid)
      refute restarted_state.crash
      assert restarted_state.base_output =~ "ready"
      refute restarted_state.base_output =~ "Breeze Error"

      Process.exit(pid, :normal)
    end)
  end

  test "server patches fixed live child invalidations without rerendering the root" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: DebugToggleRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    drain_terminal_writes()

    send(pid, {reader, {:data, "\eOQ"}})
    Process.sleep(100)

    state = :sys.get_state(pid)
    initial_render_count = state.debug_stats[:render_base_count]
    assert Map.has_key?(state.children, "debug")

    drain_terminal_writes()

    child = state.children["debug"]
    assert {:noreply, "button", true} = Breeze.ChildServer.dispatch_input(child.pid, "+")

    wait_until(fn ->
      next_state = :sys.get_state(pid)
      next_state.debug_stats[:last_render_cause] == :child_patch
    end)

    writes = drain_terminal_writes()
    next_state = :sys.get_state(pid)

    assert next_state.debug_stats[:render_base_count] == initial_render_count
    assert next_state.debug_stats[:last_render_cause] == :child_patch
    assert Enum.any?(writes, &String.contains?(&1, "Count: 2"))

    Process.exit(pid, :normal)
  end

  test "server rerenders the current root view when the code reloader detects changes" do
    parent = self()
    path = make_reload_fixture_path("reload")
    File.write!(path, "initial\n")

    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
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
    watcher_pid = :sys.get_state(:sys.get_state(pid).reloader_pid).watcher_pid
    :ok = FakeWatcher.trigger(watcher_pid, added_path)

    assert_receive {:compiled_files, files}, 1_000
    assert added_path in files

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug_stats[:last_render_cause] == :reload and state.base_output =~ "ready"
    end)

    Process.exit(pid, :normal)
  end

  test "server enters the crash screen when reloading hits a compile error" do
    capture_log(fn ->
      parent = self()
      path = make_reload_fixture_path("compile_error")
      File.write!(path, "initial\n")

      on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} =
        Breeze.Server.start_app_link(
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
        state.crash && state.base_output =~ "reload failed"
      end)

      state = :sys.get_state(pid)
      assert state.crash
      assert state.base_output =~ "Breeze Error"
      assert state.base_output =~ "reload failed"

      Process.exit(pid, :normal)
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
      Breeze.Server.start_app_link(
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
      state.base_output =~ "Count: 1"
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

    send(pid, {:reload, :code_changed, ["examples/router.exs"]})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug_stats[:last_render_cause] == :reload and state.base_output =~ "Count: 1"
    end)

    wait_until(fn ->
      state = :sys.get_state(pid)

      match?(
        [{"y", _fun}],
        state.global_keybindings
      )
    end)

    send(pid, {reader, {:data, "y"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.base_output =~ "Count: 2"
    end)

    Process.exit(pid, :normal)
  end

  test "reloaded root global keybindings do not corrupt nested router child state" do
    {:ok, config_pid} =
      Agent.start_link(fn ->
        [
          view: RootReloadWithNestedRouter,
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
      Breeze.Server.start_app_link(
        view: RootReloadWithNestedRouter,
        terminal: terminal,
        reader: reader,
        global_keybindings: refresh.()[:global_keybindings],
        reload: [
          force?: true,
          watcher_module: FakeWatcher,
          refresh_server_opts: {__MODULE__, :reload_config_server_opts, [refresh]}
        ]
      )

    wait_until(fn ->
      state = :sys.get_state(pid)
      Map.has_key?(state.children, "nested")
    end)

    Agent.update(config_pid, fn _opts ->
      [
        view: RootReloadWithNestedRouter,
        global_keybindings: [
          {"4",
           fn _event, term ->
             {:noreply, Breeze.View.assign(term, count: term.assigns.count + 1)}
           end}
        ]
      ]
    end)

    send(pid, {:reload, :code_changed, ["examples/router.exs"]})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug_stats[:last_render_cause] == :reload
    end)

    send(pid, {reader, {:data, "4"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.base_output =~ "Count: 1"
    end)

    nested = :sys.get_state(pid).children["nested"]
    nested_term = :sys.get_state(nested.pid)

    assert nested_term.assigns.router.current == :inner
    assert Map.keys(nested_term.assigns.router.routes) == [:inner]

    Process.exit(pid, :normal)
  end

  test "server falls back to a full rerender when a debug child has decorations" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: DecoratedDebugRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    Process.sleep(100)

    state = :sys.get_state(pid)
    initial_render_count = state.debug_stats[:render_base_count]
    child = state.children["debug"]

    drain_terminal_writes()

    assert {:noreply, "button", true} = Breeze.ChildServer.dispatch_input(child.pid, "+")

    wait_until(fn ->
      next_state = :sys.get_state(pid)
      next_state.debug_stats[:render_base_count] > initial_render_count
    end)

    next_state = :sys.get_state(pid)

    assert next_state.debug_stats[:render_base_count] > initial_render_count
    assert next_state.debug_stats[:last_render_cause] == :child_invalidated

    Process.exit(pid, :normal)
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

  defp drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, str} -> drain_terminal_writes([str | writes])
    after
      10 -> Enum.reverse(writes)
    end
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

  defp make_reload_fixture_path(label) do
    dir =
      Path.join(System.tmp_dir!(), "breeze-reload-#{label}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    Path.join(dir, "watched.ex")
  end

  def reload_config_server_opts(refresh) when is_function(refresh, 0) do
    refresh.()
  end
end
