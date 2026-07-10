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

  defmodule ResizeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{
         ref: make_ref(),
         size: %{width: 80, height: 24},
         resized: %{width: 120, height: 67},
         owner: Keyword.fetch!(opts, :owner)
       }}
    end

    def reader(term), do: {:ok, term.ref}

    def write(term, str) do
      send(term.owner, {:terminal_write, str})
      {:ok, term}
    end

    def resize(term), do: term.resized
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

  defmodule RootCounterChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0)}

    def render(assigns) do
      ~H"""
      <box>
        <box>Root count: {@count}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule FocusableLiveRootExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={RootCounterChild} start_opts={[]} focusable>
        </live>
      </box>
      """
    end
  end

  defmodule SnapshotCrashingChild do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(crash?: false) |> focus("root")}
    end

    def render(assigns) do
      if Map.get(assigns, :crash?, false), do: raise("snapshot boom")

      ~H"""
      <box id="root" focusable>snapshot ready</box>
      """
    end

    def handle_event(_, %{"key" => "c"}, term) do
      {:noreply, assign(term, crash?: true), invalidate: false}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule SnapshotCrashingRoot do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={SnapshotCrashingChild} start_opts={[]} focusable>
        </live>
      </box>
      """
    end
  end

  defmodule RenderOnlyChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, focus(term, "root")}

    def render(assigns) do
      ~H"""
      <box id="root" focusable>render only</box>
      """
    end
  end

  defmodule GrowingRoot do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(height: 24) |> focus("root")}
    end

    def render(assigns) do
      ~H"""
      <box id="root" focusable>
        <box :for={row <- 1..@height}>{"row #{row}"}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term), do: {:noreply, assign(term, height: 26)}
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

  defmodule LiveThenSiblingExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={RenderOnlyChild} start_opts={[]}>
        </live>
        <box id="after">After</box>
      </box>
      """
    end
  end

  defmodule PrivateUseGlyphRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box class="width-24 height-2">
        <box> _build</box>
        <box>󰂺 README.md</box>
      </box>
      """
    end
  end

  defmodule ThemeLeafLiveChild do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>Leaf</box>
      """
    end
  end

  defmodule ThemeBranchLiveChild do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="leaf" view={ThemeLeafLiveChild}>
        </live>
      </box>
      """
    end
  end

  defmodule ThemeSwitchingParent do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, focus(term, "switch")}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box id="switch" focusable>Switch</box>
        <live id="branch" view={ThemeBranchLiveChild}>
        </live>
      </box>
      """
    end

    def handle_event(_, %{"key" => "t"}, term) do
      {:noreply, put_theme(term, Breeze.Theme.builtin(:nebula))}
    end

    def handle_event(_, _, term), do: {:noreply, term}
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

  defmodule MouseScrollLiveParent do
    use Breeze.View

    def mount(_opts, term), do: {:ok, focus(term, "anchor")}

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <box id="anchor" focusable class="height-1">anchor</box>
        <live id="scroll-child" view={BufferedScrollView} class="width-full height-full">
        </live>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
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

  defmodule FastDecoration do
    @frames ["a", "b", "c"]

    def init(_items, _root_attrs, last_state),
      do: {:ok, last_state, rerender_every: 20}

    def handle_modifiers(:root, _flags, _state), do: []
    def handle_modifiers(:child, _flags, _state), do: []

    def animate(:root, box, _flags, _state, %{frame: frame} = ctx) do
      content = Enum.at(@frames, rem(frame, length(@frames)))

      case Map.get(ctx, :layout) do
        %Breeze.Viewport{left: left, top: top} ->
          {:ok, %{box | content: content}, overlays: [%{x: left, y: top, content: content}]}

        _layout ->
          %{box | content: content}
      end
    end

    def animate(:child, box, _flags, _state, _ctx), do: box
  end

  defmodule FasterDecorationRoot do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok, term |> focus("search") |> assign(query: "", loading?: false)}
    end

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <.input id="search" input-value={@query} br-change="query_changed" style="width-20"/>
        <box :if={@loading?} id="fast" implicit={FastDecoration} style="width-1">a</box>
      </box>
      """
    end

    def handle_event("query_changed", %{value: value}, term) do
      {:noreply, assign(term, query: value)}
    end

    def handle_event("show_loading", _event, term) do
      {:noreply, assign(term, loading?: true)}
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

  defmodule CustomErrorView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box>Custom Error View</box>
        <box>View: {inspect(@view)}</box>
        <box>Kind: {inspect(@kind)}</box>
        <box>Stacktrace: {length(@stacktrace)}</box>
        <box>Crash: {inspect(@crash.reason)}</box>
      </box>
      """
    end
  end

  defmodule KeybindingErrorView do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box>Keybinding Error View</box>
        <box>View: {inspect(@view)}</box>
        <.keybinding_bar keybindings={@breeze.keybindings}/>
      </box>
      """
    end
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

  defmodule PersistentToggleRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, show_child: true)}

    def render(assigns) do
      ~H"""
      <box>
        <live :if={@show_child} id="persistent" view={CounterChild} persistent={true}>
        </live>
      </box>
      """
    end

    def handle_event("toggle", _event, term) do
      {:noreply, assign(term, show_child: !term.assigns.show_child)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
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

    def mount(_opts, term) do
      {:ok, term |> assign(reload_marker: :initial) |> focus("child")}
    end

    def render(assigns) do
      ~H"""
      <box id="child" focusable>
        <live id="inner" view={NestedReloadLeaf} start_opts={[]}>
        </live>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule RootReloadWithNestedChild do
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

  defmodule InlineLivePatchRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box style="inline">
        <live id="left" view={CounterChild} start_opts={[]}>
        </live>
        <live id="right" view={CounterChild} start_opts={[]}>
        </live>
      </box>
      """
    end
  end
end

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

  test "live child layout does not shift following sibling elements" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 10}}
    {:ok, pid} = ChildServer.start(view: LiveThenSiblingExample, terminal: terminal)

    assert {:ok, _acc, _box, _decorations} =
             ChildServer.render_snapshot(pid, terminal: terminal)

    elements = ChildServer.layout_snapshot(pid).elements

    assert %Breeze.Viewport{top: child_top, height: child_height} = elements["child"]
    assert %Breeze.Viewport{left: 0, top: after_top, width: 5, height: 1} = elements["after"]
    assert after_top == child_top + child_height
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

  test "focusable live child keeps root focus when child has no local focus target" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, root_pid} = ChildServer.start(view: FocusableLiveRootExample, terminal: terminal)

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
    {:ok, root_pid} = ChildServer.start(view: MouseScrollLiveParent, terminal: terminal)

    assert {:ok, _acc, _box, _decorations} =
             ChildServer.render_snapshot(root_pid, terminal: terminal)

    %{children: %{"scroll-child" => %{pid: child_pid}}} = :sys.get_state(root_pid)
    targets = ChildServer.layout_snapshot(root_pid).mouse_targets

    assert {:noreply, "anchor", true} =
             ChildServer.dispatch_input(
               root_pid,
               wheel_event(:wheel_down, targets["scroll-child::scroll"])
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
      Breeze.Server.start_app_link(
        view: MouseScrollLiveParent,
        terminal: terminal,
        mouse: true,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

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
    send(pid, {reader, {:data, "\e[<65;#{x};#{y}M"}})

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
      ChildServer.start(
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

  test "child server stops nested live children when it terminates" do
    {:ok, pid} = ChildServer.start(view: ThemeSwitchingParent, start_opts: [])
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
    {:ok, pid} = ChildServer.start(view: DebugToggleRoot, start_opts: [])
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
    {:ok, pid} = ChildServer.start(view: PersistentToggleRoot, start_opts: [])
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

  test "server reschedules animation when a faster decoration appears" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: FasterDecorationRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

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
      Breeze.Server.start_app_link(
        view: PrivateUseGlyphRoot,
        terminal: terminal,
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

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

  test "server stops inactive non-persistent live children" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: DebugToggleRoot,
        terminal: terminal
      )

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

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: FocusableLiveRootExample,
        terminal: terminal
      )

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
      Breeze.Server.start_app_link(
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

    Process.exit(pid, :normal)
  end

  test "live snapshot call adopts crash state when child render crashes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: SnapshotCrashingRoot,
          terminal: terminal
        )

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

      Process.exit(pid, :normal)
    end)
  end

  test "requested live snapshot adopts crash state when child render crashes" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: SnapshotCrashingRoot,
          terminal: terminal
        )

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

      Process.exit(pid, :normal)
    end)
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
end

defmodule Breeze.LiveView.CrashTest do
  use Breeze.TestSupport.LiveViewCase, async: true

  import Breeze.TestSupport.LiveViewHelpers

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

  test "child server ignores missing optional view callbacks" do
    refute function_exported?(RenderOnlyChild, :handle_event, 3)
    refute function_exported?(RenderOnlyChild, :handle_info, 2)

    {:ok, pid} = ChildServer.start(view: RenderOnlyChild, start_opts: [])

    assert {:noreply, "root", false} = ChildServer.dispatch_input(pid, "x")

    assert {:noreply, "root", false} =
             ChildServer.dispatch_event(pid, :ignore_me, %{"key" => "x"})

    assert {:noreply, "root"} = ChildServer.dispatch_info(pid, :message)
  end

  test "server renders configured error view on view exceptions" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          render_errors: [view: CustomErrorView],
          global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Custom Error View" &&
          state.frame.base_output =~ "View: Breeze.LiveViewTest.CrashingView" &&
          state.frame.base_output =~ "Kind: :error" &&
          state.frame.base_output =~ "Crash: %RuntimeError"
      end)

      Process.exit(pid, :normal)
    end)
  end

  test "custom error view without keybindings ignores built-in crash keypresses" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          render_errors: [view: CustomErrorView]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Custom Error View"
      end)

      send(pid, {reader, {:data, "r"}})

      state = :sys.get_state(pid)
      assert state.crash
      assert state.frame.base_output =~ "Custom Error View"

      Process.exit(pid, :normal)
    end)
  end

  test "custom error view handles crash keypresses through render_errors keybindings" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          render_errors: [
            view: KeybindingErrorView,
            keybindings: [{"r", "Restart", :restart}]
          ]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Keybinding Error View" &&
          state.frame.base_output =~ "r" &&
          state.frame.base_output =~ "Restart"
      end)

      send(pid, {reader, {:data, "r"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        is_nil(state.crash) &&
          state.frame.base_output =~ "ready"
      end)

      Process.exit(pid, :normal)
    end)
  end

  test "custom error view copies details through render_errors keybindings" do
    parent = self()

    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          render_errors: [
            view: CustomErrorView,
            keybindings: [{"y", "Copy details", :copy_details}]
          ],
          internal: [
            clipboard: [
              copy_fun: fn text ->
                send(parent, {:copied_custom_error_details, text})
                {:ok, "test-clipboard"}
              end
            ]
          ]
        )

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)

        state.crash &&
          state.frame.base_output =~ "Custom Error View"
      end)

      send(pid, {reader, {:data, "y"}})

      assert_receive {:copied_custom_error_details, details}
      assert details =~ "Breeze Error"
      assert details =~ "CrashingView"
      assert details =~ "RuntimeError"

      wait_until(fn ->
        case :sys.get_state(pid).crash do
          %{notice: "Copied crash details to test-clipboard."} -> true
          _ -> false
        end
      end)

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

  test "crash screen q quits the server" do
    capture_log(fn ->
      terminal = Termite.Terminal.start(adapter: FakeAdapter)
      reader = terminal.reader

      {:ok, pid} =
        Breeze.Server.start_app_link(
          view: CrashingView,
          terminal: terminal,
          global_keybindings: [{"^c", "Quit", fn _event, term -> {:stop, term} end}]
        )

      ref = Process.monitor(pid)

      send(pid, {reader, {:data, "c"}})

      wait_until(fn ->
        state = :sys.get_state(pid)
        state.crash && state.frame.base_output =~ "Breeze Error"
      end)

      send(pid, {reader, {:data, "q"}})

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
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
          internal: [
            clipboard: [
              copy_fun: fn text ->
                send(parent, {:copied_crash_details, text})
                {:ok, "test-clipboard"}
              end
            ]
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

      notice_ref = :sys.get_state(pid).crash.notice_ref
      send(pid, {:clear_crash_notice, notice_ref})

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
          internal: [
            clipboard: [
              copy_fun: fn text ->
                send(parent, {:copied_crash_details, text})
                {:ok, "test-clipboard"}
              end
            ]
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
          internal: [
            clipboard: [
              timeout: 10,
              find_executable: fn "wl-copy" -> "/usr/bin/wl-copy" end,
              run_fun: fn _name, _path, _text ->
                Process.sleep(1_000)
                {:ok, "slow-copy"}
              end
            ]
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
end

defmodule Breeze.LiveView.ReloadAndFrameTest do
  use Breeze.TestSupport.LiveViewCase, async: true

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

    send(pid, {:reload, :code_changed, ["lib/breeze/view.ex"]})

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

    send(pid, {:reload, :code_changed, ["lib/breeze/view.ex"]})

    wait_until(fn ->
      state = :sys.get_state(pid)

      state.debug.stats[:last_render_cause] == :reload and
        state.start_opts == [count: 1] and
        state.frame.base_output =~ "Count: 1"
    end)

    Process.exit(pid, :normal)
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
      Breeze.Server.start_app_link(
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

    flush_debug_stats(pid)
    drain_terminal_writes()

    invalidations_before = :sys.get_state(pid).debug.stats[:child_invalidated_count] || 0

    flush_debug_stats(pid)
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

  test "sibling live child patch payload starts at the invalidated child viewport" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    payload = IO.iodata_to_binary(writes)

    assert payload =~ "\e[2J\e[H"

    Process.exit(pid, :normal)
  end

  test "terminal size override is reapplied after resize" do
    terminal = Termite.Terminal.start(adapter: ResizeAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

    Process.exit(pid, :normal)
  end

  test "incremental frame diff writes rows introduced by a height increase" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: GrowingRoot,
        terminal: terminal
      )

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

    Process.exit(pid, :normal)
  end

  test "debug pane invalidation settles instead of feeding back into its own stats stream" do
    terminal = Termite.Terminal.start(adapter: RecordingAdapter, owner: self())
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
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

  test "global stop keybindings win over inspector movement keys" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, pid} =
      Breeze.Server.start_app_link(
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
