defmodule Breeze.RuntimeTest do
  @moduledoc false

  # These fixtures are compiled once in MIX_ENV=test; the cases stay in .exs files.

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

  defmodule DeferredPauseRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0)}

    def render(assigns) do
      ~H"""
      <box>count={@count}</box>
      """
    end

    def handle_event(_, %{"key" => "+"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term, invalidate: false}
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

  defmodule TransactionalRoot do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0, crash?: false)}

    def render(%{crash?: true}), do: raise("replacement render failed")

    def render(assigns) do
      ~H"""
      <box>
        <box>count={@count}</box>
        <live id="child" view={ForkChild}>
        </live>
      </box>
      """
    end

    def handle_event(:increment, _event, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end
end

defmodule Breeze.RuntimeTestCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Breeze.TestSupport.WaitUntil
      import Breeze.RuntimeTestHelpers

      import Breeze.TestSupport.ProcessHelpers,
        only: [start_app_server: 1, stop_gen_server: 1]

      alias Breeze.RuntimeTest.{
        AnimatedImplicit,
        AnimatedRoot,
        BlockingView,
        CaptureHook,
        DeferredPauseRoot,
        FailingHook,
        FakeAdapter,
        FocusChild,
        FocusRoot,
        ForkChild,
        ForkRoot,
        HookPage,
        MountSideEffectView,
        NestedPersistentLeaf,
        NestedPersistentParent,
        NestedPersistentRoot,
        PersistentRoot,
        RecordingAdapter,
        RestoreChildrenRoot,
        StatefulImplicit,
        TaggedHook,
        TransactionalRoot
      }
    end
  end
end

defmodule Breeze.RuntimeTestHelpers do
  @moduledoc false

  def collect_hook_activity(pid, activity \\ nil, timeout \\ 500) do
    activity =
      activity ||
        %{
          events: [],
          runtime_states: []
        }

    receive do
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

  def hook_event_counts(activity, id) do
    activity.events
    |> Enum.filter(fn {event_id, _count, _metadata} -> event_id == id end)
    |> Enum.map(fn {_event_id, count, _metadata} -> count end)
    |> Enum.sort()
  end

  def hook_capture(activity, id, count) do
    Enum.find_value(activity.runtime_states, :error, fn
      {^id, ^count, result, _metadata, _diagnostics} -> result
      _capture -> false
    end)
  end

  def drain_terminal_writes(writes \\ []) do
    receive do
      {:terminal_write, content} -> drain_terminal_writes([content | writes])
    after
      2 -> Enum.reverse(writes)
    end
  end
end
