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

  defmodule HeaderedLiveChild do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, assign(term, count: 0)}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box>Captured logs</box>
        <box>Showing debug+ logs.</box>
        <box id="body" style="border-rounded width-20 height-3">Count: {@count}</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}

    def handle_info(:bump, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule HeaderedLiveRoot do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <box>Crash Handler Demo</box>
        <box>
        </box>
        <live id="child" view={HeaderedLiveChild}>
        </live>
      </box>
      """
    end
  end

  defmodule KeybindingChild do
    use Breeze.View

    def mount(_opts, term) do
      {:ok,
       term
       |> focus("save")
       |> put_local_keybindings([{"Esc", "Close"}])
       |> put_focus_keybindings("save", [{"Enter", "Save"}])}
    end

    def render(assigns) do
      ~H"""
      <box id="save" focusable>save</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule BufferedScrollView do
    use Breeze.View

    alias BackBreeze.VirtualText.Source

    def mount(_opts, term) do
      {:ok, term |> focus("scroll") |> assign(content: build_content())}
    end

    def render(assigns) do
      ~H"""
      <box
        id="scroll"
        implicit={Breeze.Implicit.Scroll}
        focusable
        class="width-screen height-screen overflow-scroll"
      >
        {@content}
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}

    defp build_content do
      Source.lazy(
        cache_key: :buffered_scroll_view,
        intrinsic_width: 12,
        line_count_fn: fn _width -> 200 end,
        slice_fn: fn start_line, visible_count, _width ->
          Enum.map(start_line..(start_line + visible_count - 1), fn line_no ->
            if line_no < 200 do
              "Line " <> String.pad_leading(Integer.to_string(line_no + 1), 3, "0")
            else
              ""
            end
          end)
        end
      )
    end
  end

  defmodule KeybindingFooterRoot do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box style="grid grid-cols-1 grid-rows-2 width-screen height-screen">
        <live id="child" view={KeybindingChild} start_opts={[]}>
        </live>
        <box id="footer" style="height-1 width-full bg-panel overflow-hidden">
          <.keybinding_bar keybindings={@breeze.keybindings}/>
        </box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule AssignEchoChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="variant">{Map.get(assigns, :variant, "none")}</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule LiveAssignsRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, variant: "muted")}

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box id="toggle" focusable>toggle</box>
        <live id="preview" view={AssignEchoChild} assigns={%{variant: @variant}}>
        </live>
      </box>
      """
    end

    def handle_event(_, %{"key" => "v"}, term) do
      next_variant = if term.assigns.variant == "muted", do: "accent", else: "muted"
      {:noreply, assign(term, variant: next_variant)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
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

  defmodule AlternateChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="alt">Alternate child</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule SwitchableLiveRoot do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, assign(term, child_view: CounterChild)}
    end

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box id="switch" focusable>switch</box>
        <live id="preview" view={@child_view} start_opts={[]}>
        </live>
      </box>
      """
    end

    def handle_event(_, %{"key" => "s"}, term) do
      next_view =
        case term.assigns.child_view do
          CounterChild -> AlternateChild
          _ -> CounterChild
        end

      {:noreply, assign(term, child_view: next_view)}
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

  defmodule DebugPaneRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term |> assign(count: 1) |> focus("button")}

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box id="button" focusable>Count: {@count}</box>
        <box style="fixed right-0 bottom-0 width-18 height-8">
          <live id="debug" view={Breeze.Debug} start_opts={[width: 18, height: 8]}>
          </live>
        </box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
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

  defmodule ReloadStateView do
    use Breeze.View

    def mount(opts, term) do
      {:ok, term |> assign(count: Keyword.get(opts, :count, 0)) |> focus("root")}
    end

    def render(assigns) do
      ~H"""
      <box id="root" focusable>Count: {@count}</box>
      """
    end

    def handle_event(_, %{"key" => "x"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
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

  test "focused child keybindings are exposed to the parent footer assign" do
    {:ok, pid} = ChildServer.start(view: KeybindingFooterRoot, start_opts: [])
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

    assert Breeze.DebugProfiler.snapshot(profile_scope) == []
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
      Map.has_key?(state.children, "debug") and state.frame.base_output =~ "Count: 1"
    end)

    state = :sys.get_state(pid)
    assert Map.has_key?(state.children, "debug")
    assert state.frame.base_output =~ "Count: 1"

    Process.exit(pid, :normal)
  end

  test "server updates live child assigns in place when dynamic assigns change" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    Process.exit(pid, :normal)
  end

  test "server coalesces repeated identical key events in the input queue" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: BufferedScrollView,
        terminal: terminal
      )

    Enum.each(1..5, fn _ -> send(pid, {reader, {:data, "\e[6~"}}) end)

    wait_until(fn ->
      state = :sys.get_state(pid)
      not state.input.flush_scheduled? and :queue.is_empty(state.input.queued_input)
    end)

    %{view_pid: view_pid} = :sys.get_state(pid)

    assert %{implicit_state: %{"scroll" => {Breeze.Implicit.Scroll, scroll_state}}} =
             Breeze.ChildServer.metadata(view_pid)

    assert scroll_state.offset_y == 23

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
          state.frame.base_output =~ "Breeze Error" &&
          state.frame.base_output =~ "CrashingView" &&
          state.frame.base_output =~ "RuntimeError"
      end)

      state = :sys.get_state(pid)

      assert state.crash
      assert state.frame.base_output =~ "Breeze Error"
      assert state.frame.base_output =~ "CrashingView"
      assert state.frame.base_output =~ "RuntimeError"
      assert state.frame.base_output =~ "Crash Details"
      assert state.frame.base_output =~ "Selected Frame"
      assert state.frame.base_output =~ "Stacktrace"
      assert state.frame.base_output =~ "boom"
      assert Breeze.ErrorView.frame_count(state.crash) > 1
      refute state.frame.base_output =~ "No structured stacktrace captured"

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

      initial_assigns =
        Breeze.ErrorView.render_assigns(CrashingView, initial_state.crash, terminal.size)

      assert initial_assigns.stacktrace_list_width > 10

      send(pid, {reader, {:data, "\t"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.crash.focused == "error-history"
      end)

      next_state = :sys.get_state(pid)
      assert next_state.crash.focused == "error-history"

      assigns = Breeze.ErrorView.render_assigns(CrashingView, next_state.crash, terminal.size)
      assert assigns.stacktrace_list_width == 10
      assert assigns.history_scroll_width > 50

      Process.exit(pid, :normal)
    end)
  end

  test "crash details text wraps to the details pane width" do
    crash = %{
      kind: :error,
      reason:
        RuntimeError.exception(
          "a long crash message with enough words to wrap inside the details pane instead of scrolling horizontally"
        ),
      stacktrace: [
        {Very.Long.CrashHandler.ModuleName.ForWrapping, :function_name_with_a_long_suffix, 3,
         [file: ~c"test/support/a/very/long/path/to/a/crashing/file_for_wrapping.exs", line: 123]}
      ],
      selected_index: nil,
      focused: "error-stacktrace",
      implicit_state: %{}
    }

    assigns = Breeze.ErrorView.render_assigns(CrashingView, crash, %{width: 60, height: 20})

    assert assigns.history_content_width == assigns.history_scroll_width
    assert Enum.any?(assigns.history_lines, &String.contains?(&1, "horizontally"))
    assert Enum.all?(assigns.history_lines, &(String.length(&1) <= assigns.history_scroll_width))
  end

  test "crash screen keypresses patch rows instead of forcing full redraws" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      drain_terminal_writes()
      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      drain_terminal_writes()
      send(pid, {reader, {:data, "\t"}})

      writes =
        wait_until(fn ->
          writes = drain_terminal_writes()

          if :sys.get_state(pid).crash.focused == "error-history" and writes != [] do
            IO.iodata_to_binary(writes)
          else
            false
          end
        end)

      refute writes =~ "\e[2J"
      assert writes =~ "Crash Details"

      Process.exit(pid, :normal)
    end)
  end

  test "crash screen copies plain details when clipboard is available" do
    parent = self()

    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          clipboard: [
            copy_fun: fn text ->
              send(parent, {:copied_crash_details, text})
              {:ok, "test-clipboard"}
            end
          ],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      send(pid, {reader, {:data, "y"}})

      assert_receive {:copied_crash_details, details}
      assert details =~ "Breeze Error"
      assert details =~ "Crash Details"
      assert details =~ "CrashingView"
      assert details =~ "RuntimeError"
      assert details =~ "boom"

      wait_until(fn ->
        :sys.get_state(pid).frame.base_output =~ "Copied crash details to test-clipboard."
      end)

      Process.sleep(1_050)

      wait_until(fn ->
        output = :sys.get_state(pid).frame.base_output

        output =~ "y copies details" and
          not String.contains?(output, "Copied crash details to test-clipboard.")
      end)

      Process.exit(pid, :normal)
    end)
  end

  test "crash screen accepts uppercase yank key" do
    parent = self()

    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          clipboard: [
            copy_fun: fn text ->
              send(parent, {:copied_crash_details, text})
              {:ok, "test-clipboard"}
            end
          ],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      send(pid, {reader, {:data, "Y"}})

      assert_receive {:copied_crash_details, details}
      assert details =~ "Breeze Error"
      assert details =~ "RuntimeError"

      wait_until(fn ->
        :sys.get_state(pid).frame.base_output =~ "Copied crash details to test-clipboard."
      end)

      Process.exit(pid, :normal)
    end)
  end

  test "crash screen prints details to scrollback when clipboard copy times out" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          clipboard: [
            timeout: 10,
            find_executable: fn "wl-copy" -> "/usr/bin/wl-copy" end,
            run_fun: fn _name, _path, _text ->
              Process.sleep(1_000)
              {:ok, "slow-copy"}
            end
          ],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      drain_terminal_writes()

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      drain_terminal_writes()
      send(pid, {reader, {:data, "y"}})

      writes =
        wait_until(fn ->
          writes = drain_terminal_writes()
          output = IO.iodata_to_binary(writes)

          if output =~ "Crash Details" and output =~ "Clipboard copy failed: :timeout" and
               output =~ "Press q to quit, r to restart." do
            output
          else
            false
          end
        end)

      assert writes =~ "\e[?1049l"
      assert writes =~ "Breeze Error"
      assert writes =~ "CrashingView"
      assert writes =~ "RuntimeError"
      assert :sys.get_state(pid).alt_screen_active? == false

      drain_terminal_writes()
      send(pid, {reader, {:data, "r"}})

      restarted_state =
        wait_until(fn ->
          state = :sys.get_state(pid)

          if is_nil(state.crash) and state.frame.base_output =~ "ready" do
            state
          else
            false
          end
        end)

      assert restarted_state.alt_screen_active? == true

      restart_writes = IO.iodata_to_binary(drain_terminal_writes())
      assert restart_writes =~ "\e[?1049h"
      assert restart_writes =~ "ready"

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

        is_nil(state.crash) and state.frame.base_output =~ "ready" and
          not String.contains?(state.frame.base_output, "Breeze Error")
      end)

      restarted_state = :sys.get_state(pid)
      refute restarted_state.crash
      assert restarted_state.frame.base_output =~ "ready"
      refute restarted_state.frame.base_output =~ "Breeze Error"

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

    wait_until(fn ->
      state = :sys.get_state(pid)
      if Map.has_key?(state.children, "debug"), do: state, else: false
    end)

    state = :sys.get_state(pid)
    initial_render_count = state.debug.stats[:render_base_count]
    assert Map.has_key?(state.children, "debug")

    drain_terminal_writes()

    child = state.children["debug"]
    assert {:noreply, "button", true} = Breeze.ChildServer.dispatch_input(child.pid, "+")

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if Enum.any?(writes, &String.contains?(&1, "Count: 2")), do: writes, else: false
      end)

    next_state = :sys.get_state(pid)

    assert next_state.debug.stats[:render_base_count] == initial_render_count
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
      state.debug.stats[:last_render_cause] == :reload and state.frame.base_output =~ "ready"
    end)

    Process.exit(pid, :normal)
  end

  test "debug pane does not flash an empty stats snapshot on first open" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: DebugToggleRoot,
        terminal: terminal,
        debug_push_interval_ms: 20,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

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
        state.crash && state.frame.base_output =~ "reload failed"
      end)

      state = :sys.get_state(pid)
      assert state.crash
      assert state.frame.base_output =~ "Breeze Error"
      assert state.frame.base_output =~ "reload failed"

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

    send(pid, {:reload, :code_changed, ["examples/router.exs"]})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.debug.stats[:last_render_cause] == :reload and state.frame.base_output =~ "Count: 1"
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
      state.frame.base_output =~ "Count: 2"
    end)

    Process.exit(pid, :normal)
  end

  test "refresh_server_opts can receive root metadata and preserve state on reload restart" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    send(pid, {:reload, :code_changed, ["examples/router.exs"]})

    wait_until(fn ->
      state = :sys.get_state(pid)

      state.debug.stats[:last_render_cause] == :reload and
        state.start_opts == [count: 1] and
        state.frame.base_output =~ "Count: 1"
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
      state.debug.stats[:last_render_cause] == :reload
    end)

    send(pid, {reader, {:data, "4"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      state.frame.base_output =~ "Count: 1"
    end)

    nested = :sys.get_state(pid).children["nested"]
    nested_term = :sys.get_state(nested.pid)

    assert nested_term.assigns.router.current == :inner
    assert Map.keys(nested_term.assigns.router.routes) == [:inner]

    Process.exit(pid, :normal)
  end

  test "debug stats updates do not invalidate the parent just to refresh the pane" do
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

    wait_until(fn ->
      state = :sys.get_state(pid)
      Map.has_key?(state.children, "debug")
    end)

    Process.sleep(40)
    drain_terminal_writes()

    invalidations_before = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    Process.sleep(40)
    writes = drain_terminal_writes()
    invalidations_after = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    assert writes == []
    assert invalidations_after == invalidations_before

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

    Process.exit(pid, :normal)
  end

  test "child patch payload starts at the live root even when the live placeholder has no explicit size" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    Process.exit(pid, :normal)
  end

  test "winch forces a full redraw to resync the compositor" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    assert Enum.any?(writes, &String.starts_with?(&1, "\e[2J\e[H"))

    Process.exit(pid, :normal)
  end

  test "debug pane invalidation settles instead of feeding back into its own stats stream" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: DebugPaneRoot,
        terminal: terminal,
        debug_push_interval_ms: 20,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    drain_terminal_writes()
    initial_render_count = :sys.get_state(pid).debug.stats[:render_base_count] || 0

    send(pid, {reader, {:data, "+"}})

    wait_until(fn ->
      state = :sys.get_state(pid)
      (state.debug.stats[:render_base_count] || 0) > initial_render_count
    end)

    Process.sleep(40)
    drain_terminal_writes()

    invalidations_before = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    Process.sleep(40)
    writes = drain_terminal_writes()
    invalidations_after = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    assert writes == []
    assert invalidations_after == invalidations_before

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
    case fun.() do
      false ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)

      nil ->
        Process.sleep(10)
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

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: SwitchableLiveRoot,
        terminal: terminal
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    drain_terminal_writes()

    send(pid, {terminal.reader, {:data, "s"}})

    writes =
      wait_until(fn ->
        writes = drain_terminal_writes()
        if IO.iodata_to_binary(writes) =~ "Alternate child", do: writes, else: false
      end)

    assert IO.iodata_to_binary(writes) =~ "Alternate child"
  end
end
