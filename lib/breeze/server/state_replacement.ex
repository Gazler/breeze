defmodule Breeze.Server.StateReplacement do
  @moduledoc false

  alias Breeze.Runtime.State, as: RuntimeState
  alias Breeze.Server.{Error, FrameDisplay, Input}
  alias Breeze.Server.State

  def prepare(state, %RuntimeState{root: %RuntimeState.View{} = root} = runtime_state) do
    hooks = state.rendered.runtime_hooks

    state =
      state
      |> FrameDisplay.discard()
      |> put_hooks([])

    terminate_processes(state)

    global_keybindings =
      case root.term do
        %Breeze.Term{global_keybindings: keybindings} when is_list(keybindings) -> keybindings
        _term -> state.input.global_keybindings
      end

    state =
      state
      |> Map.put(:view_pid, nil)
      |> Map.put(:start_opts, runtime_state.start_opts || [])
      |> Map.put(:children, %{})
      |> Map.put(:crash, nil)
      |> Map.put(:crash_scrollback?, false)
      |> Input.reset_pipeline(global_keybindings: global_keybindings)
      |> Map.put(:frame, %State.Frame{last_render_at: System.monotonic_time(:millisecond)})
      |> Map.put(:rendered, %State.Rendered{
        tracking_table: state.rendered.tracking_table,
        runtime_hooks: []
      })

    context = %{
      hooks: hooks,
      root_state: root_state(root, runtime_state.focused),
      children: root.children
    }

    {state, context}
  end

  def restore_hooks(state, hooks) when is_list(hooks), do: put_hooks(state, hooks)

  def cleanup(state) do
    terminate_processes(state)

    Enum.each(state.children, fn {_id, child} ->
      case Map.get(child, :ref) do
        ref when is_reference(ref) -> Process.demonitor(ref, [:flush])
        _ref -> :ok
      end
    end)

    %{state | view_pid: nil, children: %{}}
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

  def error(reason) do
    RuntimeError.exception("could not replace runtime state: #{inspect(reason)}")
  end

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

  defp put_hooks(state, hooks) do
    rendered = struct!(state.rendered, runtime_hooks: hooks)
    %{state | rendered: rendered}
  end

  defp live_id(nil, id), do: id
  defp live_id(prefix, id), do: prefix <> "::" <> id
end
