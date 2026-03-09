defmodule Breeze.LoggerCollector do
  @moduledoc false

  use GenServer

  @name __MODULE__
  @default_max_entries 1000
  @default_handler_id :default

  def ensure_started(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: @name) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  def subscribe(pid \\ self()) do
    {:ok, _collector} = ensure_started()
    GenServer.call(@name, {:subscribe, pid})
  end

  def clear do
    {:ok, _collector} = ensure_started()
    GenServer.call(@name, :clear)
  end

  def entries do
    {:ok, _collector} = ensure_started()
    GenServer.call(@name, :entries)
  end

  @impl true
  def init(opts) do
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)
    mute_console = Keyword.get(opts, :mute_console, true)
    :ok = Breeze.LoggerHandler.ensure_installed(self())

    {:ok,
     %{
       entries: [],
       max_entries: max_entries,
       mute_console: mute_console,
       subscribers: %{},
       default_handler_level: nil
     }}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    ref = Process.monitor(pid)
    send(pid, {:logger_snapshot, state.entries})

    subscribers =
      case Map.pop(state.subscribers, pid) do
        {nil, subscribers} ->
          Map.put(subscribers, pid, ref)

        {old_ref, subscribers} ->
          Process.demonitor(old_ref, [:flush])
          Map.put(subscribers, pid, ref)
      end

    state =
      %{state | subscribers: subscribers}
      |> maybe_mute_console()

    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    Enum.each(Map.keys(state.subscribers), &send(&1, {:logger_snapshot, []}))
    {:reply, :ok, %{state | entries: []}}
  end

  def handle_call(:entries, _from, state) do
    {:reply, state.entries, state}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    entries =
      state.entries
      |> Kernel.++([entry])
      |> Enum.take(-state.max_entries)

    Enum.each(Map.keys(state.subscribers), &send(&1, {:logger_entry, entry}))
    {:noreply, %{state | entries: entries}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    subscribers =
      state.subscribers
      |> Enum.reject(fn {_pid, monitor_ref} -> monitor_ref == ref end)
      |> Map.new()

    state =
      %{state | subscribers: subscribers}
      |> maybe_restore_console()

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    _ = restore_default_handler_level(state.default_handler_level)
    :ok
  end

  defp maybe_mute_console(%{mute_console: false} = state), do: state

  defp maybe_mute_console(%{default_handler_level: level} = state) when not is_nil(level),
    do: state

  defp maybe_mute_console(%{subscribers: subscribers} = state) when map_size(subscribers) > 0 do
    case :logger.get_handler_config(@default_handler_id) do
      {:ok, %{level: level}} ->
        case :logger.set_handler_config(@default_handler_id, :level, :none) do
          :ok -> %{state | default_handler_level: level}
          _ -> state
        end

      _ ->
        state
    end
  end

  defp maybe_mute_console(state), do: state

  defp maybe_restore_console(%{mute_console: false} = state), do: state

  defp maybe_restore_console(%{subscribers: subscribers} = state)
       when map_size(subscribers) == 0 do
    case restore_default_handler_level(state.default_handler_level) do
      :ok -> %{state | default_handler_level: nil}
      _ -> state
    end
  end

  defp maybe_restore_console(state), do: state

  defp restore_default_handler_level(nil), do: :ok

  defp restore_default_handler_level(level) do
    :logger.set_handler_config(@default_handler_id, :level, level)
  end
end
