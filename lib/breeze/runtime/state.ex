defmodule Breeze.Runtime.State do
  @moduledoc """
  Opaque state exported from a running Breeze view tree.

  Runtime state contains the application and renderer data required to start
  or replace a view runtime, including assigns, focus, implicit state, and
  nested live-view state. It intentionally omits process identifiers,
  monitors, render timers, terminal handles, and invalidation callbacks.

  Treat this struct and its nested values as opaque. Captured assigns may hold
  arbitrary application terms, so state is only intended for short-lived use
  in the same BEAM instance with the same Breeze and application code. It does
  not provide a persistent storage or migration format.
  """

  alias __MODULE__.View

  @version 1
  @default_timeout 5_000

  defstruct version: @version,
            view: nil,
            start_opts: [],
            focused: nil,
            root: nil

  @opaque t :: %__MODULE__{
            version: pos_integer(),
            view: module(),
            start_opts: keyword(),
            focused: String.t() | nil,
            root: View.t()
          }

  @doc false
  def capture_server(state, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with {:ok, root} <- capture_view_pid(state.view_pid, timeout),
         {:ok, root} <- attach_server_children(root, state.children || %{}, timeout) do
      {:ok,
       %__MODULE__{
         view: state.view,
         start_opts: state.start_opts || [],
         focused: state.focused,
         root: root
       }}
    end
  end

  @doc false
  def capture_view(term, timeout \\ @default_timeout) do
    with {:ok, children} <- capture_local_children(term.children || %{}, timeout) do
      {:ok,
       %View{
         term: sanitize_term(term),
         children: children
       }}
    end
  end

  @doc false
  def put_child(%View{} = state, [id], child) when is_binary(id) do
    {:ok, %{state | children: Map.put(state.children, id, child)}}
  end

  def put_child(%View{} = state, [id | rest], child) when is_binary(id) do
    case Map.get(state.children, id) do
      %{state: %View{} = child_state} = entry ->
        with {:ok, child_state} <- put_child(child_state, rest, child) do
          entry = %{entry | state: child_state}
          {:ok, %{state | children: Map.put(state.children, id, entry)}}
        end

      _ ->
        {:error, {:missing_state_parent, id, rest}}
    end
  end

  defp capture_view_pid(pid, timeout) when is_pid(pid) do
    Breeze.ChildServer.runtime_state(pid, timeout)
  catch
    :exit, reason -> {:error, {:runtime_state_exit, pid, reason}}
  end

  defp capture_view_pid(pid, _timeout), do: {:error, {:invalid_view_pid, pid}}

  defp capture_local_children(children, timeout) do
    Enum.reduce_while(children, {:ok, %{}}, fn {id, child}, {:ok, acc} ->
      case capture_child_entry(child, timeout) do
        {:ok, entry} -> {:cont, {:ok, Map.put(acc, id, entry)}}
        {:skip, _reason} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, {id, reason}}}
      end
    end)
  end

  defp attach_server_children(root, children, timeout) do
    children
    |> Enum.sort_by(fn {id, _child} -> length(live_path(id)) end)
    |> Enum.reduce_while({:ok, root}, fn {full_id, child}, {:ok, acc} ->
      case capture_child_entry(child, timeout) do
        {:ok, entry} ->
          case put_child(acc, live_path(full_id), entry) do
            {:ok, acc} ->
              {:cont, {:ok, acc}}

            {:error, {:missing_state_parent, _id, _rest}} ->
              {:cont, put_child(acc, [to_string(full_id)], entry)}

            {:error, reason} ->
              {:halt, {:error, {full_id, reason}}}
          end

        {:skip, _reason} ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, {full_id, reason}}}
      end
    end)
  end

  defp capture_child_entry(%{pid: pid} = child, timeout) when is_pid(pid) do
    if Process.alive?(pid) do
      with {:ok, runtime_state} <- capture_view_pid(pid, timeout) do
        {:ok,
         %{
           view: Map.get(child, :view) || runtime_state.term.view,
           start_opts: Map.get(child, :start_opts, []),
           assigns: Map.get(child, :assigns, %{}),
           persistent: Map.get(child, :persistent, false),
           state: runtime_state
         }}
      end
    else
      {:skip, :dead}
    end
  end

  defp capture_child_entry(_child, _timeout), do: {:skip, :invalid}

  defp sanitize_term(%Breeze.Term{} = term) do
    assigns =
      case term.assigns do
        assigns when is_map(assigns) -> Map.delete(assigns, :__invalidate__)
        assigns -> assigns
      end

    %{
      term
      | server: nil,
        child_view_supervisor: nil,
        terminal: nil,
        reader: nil,
        assigns: assigns,
        children: %{},
        wheel_handoffs: %{},
        wheel_target_lock: nil,
        render_timer: nil,
        input_routing_signature: nil
    }
  end

  defp live_path(id) when is_binary(id), do: String.split(id, "::", trim: true)
  defp live_path(id), do: [to_string(id)]
end
