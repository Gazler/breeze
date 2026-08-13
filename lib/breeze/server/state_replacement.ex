defmodule Breeze.Server.StateReplacement do
  @moduledoc false

  alias Breeze.Runtime.State, as: RuntimeState
  alias Breeze.Server.{Error, FrameDisplay, Input}
  alias Breeze.Server.State

  def prepare(state, %RuntimeState{root: %RuntimeState.View{} = root} = runtime_state) do
    global_keybindings =
      case root.term do
        %Breeze.Term{global_keybindings: keybindings} when is_list(keybindings) -> keybindings
        _term -> state.input.global_keybindings
      end

    candidate =
      state
      |> Map.put(:terminal, staging_terminal(state.terminal))
      |> Map.put(:view_pid, nil)
      |> Map.put(:start_opts, runtime_state.start_opts || [])
      |> Map.put(:children, %{})
      |> Map.put(:crash, nil)
      |> Map.put(:crash_scrollback?, false)
      |> Input.reset_pipeline(global_keybindings: global_keybindings)
      |> Map.put(:frame, %State.Frame{
        last_render_at: System.monotonic_time(:millisecond),
        display_sys_timeout: state.frame.display_sys_timeout
      })
      |> Map.put(:debug, staging_debug(state.debug))
      |> Map.put(:inspector_state, staging_inspector(state.inspector_state))
      |> Map.put(:rendered, %State.Rendered{
        tracking_table: state.rendered.tracking_table,
        runtime_hooks: []
      })

    context = %{
      terminal: state.terminal,
      hooks: state.rendered.runtime_hooks,
      debug: state.debug,
      inspector_state: state.inspector_state,
      root_state: root_state(root, runtime_state.focused),
      children: root.children
    }

    {candidate, context}
  end

  def activate(candidate, context) do
    candidate = FrameDisplay.cancel_animation(candidate)

    case put_runtime_terminal(candidate, context.terminal) do
      :ok ->
        debug =
          struct!(candidate.debug,
            subscribers: context.debug.subscribers,
            push_timer: context.debug.push_timer
          )

        inspector_state =
          struct!(candidate.inspector_state,
            config: context.inspector_state.config,
            subscribers: context.inspector_state.subscribers
          )

        frame =
          struct!(candidate.frame,
            last_payload: nil,
            last_lines: nil,
            last_overlays: []
          )

        {:ok,
         candidate
         |> Map.put(:terminal, context.terminal)
         |> Map.put(:debug, debug)
         |> Map.put(:inspector_state, inspector_state)
         |> Map.put(:frame, frame)
         |> put_hooks(context.hooks)}

      {:error, reason} ->
        {:error, reason, candidate}
    end
  end

  def commit(original, candidate) do
    _ = FrameDisplay.discard(original)
    terminate_processes(original)
    candidate
  end

  def rollback(candidate) do
    candidate = FrameDisplay.cancel_animation(candidate)
    terminate_processes(candidate)
    demonitor_children(candidate.children)
    :ok
  end

  def ready?(state) do
    is_nil(state.crash) and alive?(state.view_pid) and
      Enum.all?(state.children, fn {_id, child} -> alive?(Map.get(child, :pid)) end)
  end

  def failure(state) do
    case state.crash do
      nil -> :runtime_stopped_during_staging
      crash -> crash
    end
  end

  def start_children(state, children) when is_map(children) do
    children
    |> flatten_children()
    |> Enum.reduce_while({:ok, state}, fn {child_id, child}, {:ok, state} ->
      case start_child(state, child_id, child) do
        {:ok, restored} ->
          {:cont, {:ok, %{state | children: Map.put(state.children, child_id, restored)}}}

        {:error, reason} ->
          {:halt, {:error, {child_id, reason}, state}}
      end
    end)
  end

  def start_children(state, _children), do: {:error, :invalid_runtime_state_children, state}

  defp root_state(%RuntimeState.View{term: %Breeze.Term{} = term} = root, focused) do
    %{root | term: %{term | focused: focused}, children: %{}}
  end

  defp root_state(%RuntimeState.View{} = root, _focused), do: %{root | children: %{}}

  defp flatten_children(children, prefix \\ nil) do
    children
    |> Enum.sort_by(fn {id, _child} -> to_string(id) end)
    |> Enum.flat_map(fn {id, child} ->
      child_id = live_id(prefix, to_string(id))

      descendants =
        case Map.get(child, :state) do
          %RuntimeState.View{children: children} -> children
          _state -> %{}
        end

      [{child_id, child} | flatten_children(descendants, child_id)]
    end)
  end

  defp start_child(
         state,
         child_id,
         %{
           view: view,
           start_opts: start_opts,
           assigns: assigns,
           state: %RuntimeState.View{} = runtime_state
         } = child
       ) do
    parent = self()
    runtime_state = %{runtime_state | children: %{}}
    persistent = Map.get(child, :persistent, false)

    opts = [
      view: view,
      start_opts: start_opts,
      assigns: assigns,
      runtime_state: runtime_state,
      server: self(),
      terminal: state.terminal,
      theme: state.theme,
      apply_theme_defaults?: state.apply_theme_defaults?,
      process_flags: state.child_process_flags || [],
      render_tree?: Breeze.Inspector.enabled?(state),
      invalidate: fn -> send(parent, {:child_invalidated, child_id}) end
    ]

    result =
      Error.safe_call(fn ->
        Breeze.ChildViewSupervisor.start_child(state.child_view_supervisor, opts)
      end)

    case result do
      {:ok, {:ok, pid}} ->
        {:ok,
         %{
           pid: pid,
           ref: Process.monitor(pid),
           view: view,
           start_opts: start_opts,
           assigns: assigns,
           attrs: [
             id: child_id,
             view: view,
             start_opts: start_opts,
             assigns: assigns,
             persistent: persistent
           ],
           persistent: persistent
         }}

      {:ok, other} ->
        {:error, {:unexpected_child_start_result, other}}

      {:crash, crash} ->
        {:error, crash}
    end
  end

  defp start_child(_state, _child_id, _child), do: {:error, :invalid_runtime_state}

  defp terminate_processes(state) do
    state.children
    |> Map.values()
    |> Enum.map(&Map.get(&1, :pid))
    |> then(&[state.view_pid | &1])
    |> Enum.uniq()
    |> Enum.each(&Breeze.ChildViewSupervisor.terminate_child(state.child_view_supervisor, &1))
  end

  defp demonitor_children(children) do
    Enum.each(children, fn {_id, child} ->
      case Map.get(child, :ref) do
        ref when is_reference(ref) -> Process.demonitor(ref, [:flush])
        _ref -> :ok
      end
    end)
  end

  defp put_runtime_terminal(state, terminal) do
    state.children
    |> Map.values()
    |> Enum.map(&Map.get(&1, :pid))
    |> then(&[state.view_pid | &1])
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn pid, :ok ->
      case Error.safe_call(fn -> Breeze.ChildServer.put_terminal(pid, terminal) end) do
        {:ok, :ok} -> {:cont, :ok}
        {:ok, result} -> {:halt, {:error, {:unexpected_terminal_update_result, result}}}
        {:crash, crash} -> {:halt, {:error, crash}}
      end
    end)
  end

  defp staging_terminal(%Termite.Terminal{} = terminal) do
    %{terminal | adapter: {__MODULE__.TerminalAdapter, %{size: terminal.size}}}
  end

  defp staging_debug(debug) do
    struct!(debug, subscribers: MapSet.new(), push_timer: make_ref())
  end

  defp staging_inspector(inspector) do
    struct!(inspector,
      config: local_inspector_config(inspector.config),
      subscribers: MapSet.new()
    )
  end

  defp local_inspector_config(false), do: false
  defp local_inspector_config(nil), do: false
  defp local_inspector_config(true), do: [remote: false]

  defp local_inspector_config(config) when is_list(config),
    do: Keyword.put(config, :remote, false)

  defp local_inspector_config(config), do: config

  defp alive?(pid), do: is_pid(pid) and Process.alive?(pid)

  defp put_hooks(state, hooks) do
    rendered = struct!(state.rendered, runtime_hooks: hooks)
    %{state | rendered: rendered}
  end

  defp live_id(nil, id), do: id
  defp live_id(prefix, id), do: prefix <> "::" <> id
end

defmodule Breeze.Server.StateReplacement.TerminalAdapter do
  @moduledoc false

  @behaviour Termite.Terminal.Adapter

  @impl true
  def start(opts), do: {:ok, %{size: Keyword.get(opts, :size, %{width: 80, height: 24})}}

  @impl true
  def reader(_state), do: {:ok, make_ref()}

  @impl true
  def resize(state), do: state.size

  @impl true
  def write(state, _content), do: {:ok, state}
end
