defmodule Breeze.LiveViewTest do
  @moduledoc false

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

  defmodule RenderCrashingChild do
    use Breeze.View

    def render(_assigns), do: raise("nested render boom")
  end

  defmodule RenderCrashingRoot do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={RenderCrashingChild} start_opts={[]} focusable>
        </live>
      </box>
      """
    end
  end

  defmodule StatefulCrashRoot do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> assign(slide: 1) |> focus("child::boom")}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box>{"slide #{@slide}"}</box>
        <live id="child" view={Breeze.LiveViewTest.CrashingView} start_opts={[]} focusable>
        </live>
      </box>
      """
    end

    def handle_info({:set_slide, slide}, term), do: {:noreply, assign(term, slide: slide)}
    def handle_info(_message, term), do: {:noreply, term}
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

  defmodule MountedThemeLiveParent do
    use Breeze.View

    def mount(_opts, term) do
      {:ok,
       term
       |> put_theme(Breeze.Theme.builtin(:gruvbox))
       |> focus("switch")}
    end

    def render(assigns) do
      ~H"""
      <box>
        <box id="switch" focusable>Switch</box>
        <live id="themed-child" view={ThemeLeafLiveChild}>
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

  defmodule ContainerDecoration do
    def init(_items, _root_attrs, last_state),
      do: {:ok, last_state, rerender_every: 10_000}

    def handle_modifiers(:root, _flags, _state), do: []
    def handle_modifiers(:child, _flags, _state), do: []
    def animate(:root, box, _flags, _state, _ctx), do: box
    def animate(:child, box, _flags, _state, _ctx), do: box
  end

  defmodule DecoratedContainerRoot do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="container" implicit={ContainerDecoration} style="border-rounded width-24 height-6">
        <live id="child" view={CounterChild} start_opts={[]}>
        </live>
      </box>
      """
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
