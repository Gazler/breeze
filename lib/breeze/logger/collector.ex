defmodule Breeze.Logger.Collector do
  @moduledoc """
  Supervised storage and handler lifecycle for Breeze log capture.

  A single Breeze server starts an ephemeral collector when log capture is
  enabled. Applications running multiple Breeze sessions can instead add this
  module before those sessions in their own supervision tree:

      children = [
        Breeze.Logger.Collector,
        {Breeze.Server, view: MyApp.View, logger: :attach}
      ]

  Use a `:rest_for_one` or `:one_for_all` strategy when the Breeze sessions
  should restart after their shared collector.
  """

  use GenServer

  @name __MODULE__
  @default_max_entries 1_000
  @default_handler_id :default

  @doc """
  Starts the collector.

  Only one collector is supported per VM because Erlang logger handlers are
  VM-global.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc false
  def ensure_started(opts \\ []) do
    case Process.whereis(@name) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        case start_link(opts) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  @doc false
  def configure(config), do: configure(self(), config)

  @doc false
  def configure(owner, config) when is_pid(owner) do
    with {:ok, normalized} <- normalize_config(config) do
      call({:configure, owner, normalized})
    end
  end

  @doc false
  def configure(owner, config, runtime_opts) when is_pid(owner) and is_list(runtime_opts) do
    with {:ok, normalized} <- normalize_config(config) do
      normalized =
        if normalized == :disabled do
          normalized
        else
          Map.merge(normalized, %{
            remote_inspector?: Keyword.get(runtime_opts, :remote_inspector, false),
            view: Keyword.get(runtime_opts, :view)
          })
        end

      call({:configure, owner, normalized})
    end
  end

  @doc false
  def release(owner \\ self()) when is_pid(owner) do
    call({:release, owner})
  end

  @doc false
  def subscribe(pid \\ self()) when is_pid(pid) do
    call({:subscribe, pid})
  end

  @doc false
  def clear do
    call(:clear)
  end

  @doc false
  def entries do
    call(:entries)
  end

  @doc false
  def status do
    call(:status)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       entries: :queue.new(),
       entry_count: 0,
       configurations: %{},
       subscribers: %{},
       default_handler_config: nil,
       handler_installed?: false,
       ephemeral?: Keyword.get(opts, :ephemeral, false)
     }}
  end

  @impl true
  def handle_call({:configure, owner, :disabled}, _from, state) do
    {configuration, configurations} = Map.pop(state.configurations, owner)
    demonitor(configuration)
    reply_with_synced_handler(%{state | configurations: configurations}, stop_if_idle?: true)
  end

  def handle_call({:configure, owner, config}, _from, state) do
    {old_configuration, configurations} = Map.pop(state.configurations, owner)
    demonitor(old_configuration)

    configuration = Map.put(config, :ref, Process.monitor(owner))
    state = %{state | configurations: Map.put(configurations, owner, configuration)}
    reply_with_synced_handler(state)
  end

  def handle_call({:release, owner}, _from, state) do
    {configuration, configurations} = Map.pop(state.configurations, owner)
    demonitor(configuration)
    reply_with_synced_handler(%{state | configurations: configurations}, stop_if_idle?: true)
  end

  def handle_call({:subscribe, pid}, _from, state) do
    {old_subscription, subscribers} = Map.pop(state.subscribers, pid)
    demonitor(old_subscription)

    send(pid, {:logger_snapshot, entries_to_list(state)})
    subscription = %{ref: Process.monitor(pid)}
    {:reply, :ok, %{state | subscribers: Map.put(subscribers, pid, subscription)}}
  end

  def handle_call(:clear, _from, state) do
    Enum.each(Map.keys(state.subscribers), &send(&1, {:logger_snapshot, []}))
    state = %{state | entries: :queue.new(), entry_count: 0}
    maybe_publish_logs(state)
    {:reply, :ok, state}
  end

  def handle_call(:entries, _from, state) do
    {:reply, entries_to_list(state), state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      configured?: map_size(state.configurations) > 0,
      modes: state.configurations |> Map.values() |> Enum.map(& &1.mode) |> Enum.uniq(),
      handler_installed?: state.handler_installed?,
      replacing_default?: not is_nil(state.default_handler_config),
      max_entries: effective_max_entries(state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    entry = normalize_entry(entry)

    {entries, entry_count} =
      put_entry(state.entries, state.entry_count, entry, effective_max_entries(state))

    Enum.each(Map.keys(state.subscribers), &send(&1, {:logger_entry, entry}))
    maybe_publish_log_entry(state, entry)
    {:noreply, %{state | entries: entries, entry_count: entry_count}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    configurations = reject_monitor(state.configurations, ref)
    subscribers = reject_monitor(state.subscribers, ref)

    state = %{state | configurations: configurations, subscribers: subscribers}

    case sync_handler(state) do
      {:ok, %{ephemeral?: true, configurations: configurations} = state}
      when map_size(configurations) == 0 ->
        {:stop, :normal, state}

      {:ok, state} ->
        {:noreply, state}

      {:error, _reason, state} ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    _ = restore_default_handler(state.default_handler_config)
    _ = Breeze.Logger.Handler.remove()
    :ok
  end

  defp reply_with_synced_handler(state, opts \\ []) do
    case sync_handler(state) do
      {:ok, state} ->
        maybe_publish_logs(state)

        if state.ephemeral? and map_size(state.configurations) == 0 and
             Keyword.get(opts, :stop_if_idle?, false) do
          {:stop, :normal, :ok, state}
        else
          {:reply, :ok, state}
        end

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp sync_handler(state) do
    capture? = map_size(state.configurations) > 0
    replace? = Enum.any?(state.configurations, fn {_pid, config} -> config.mode == :replace end)

    with {:ok, state} <- sync_capture_handler(state, capture?),
         {:ok, state} <- sync_default_handler(state, replace?),
         {:ok, state} <- remove_unused_handler(state, capture?) do
      {:ok, state}
    end
  end

  defp sync_capture_handler(%{handler_installed?: true} = state, true), do: {:ok, state}

  defp sync_capture_handler(state, true) do
    case Breeze.Logger.Handler.ensure_installed(self()) do
      :ok -> {:ok, %{state | handler_installed?: true}}
      other -> {:error, {:install_handler, other}, state}
    end
  end

  defp sync_capture_handler(state, false), do: {:ok, state}

  defp sync_default_handler(%{default_handler_config: config} = state, true)
       when not is_nil(config),
       do: {:ok, state}

  defp sync_default_handler(state, true) do
    case :logger.get_handler_config(@default_handler_id) do
      {:ok, config} ->
        case :logger.set_handler_config(@default_handler_id, :level, :none) do
          :ok -> {:ok, %{state | default_handler_config: config}}
          other -> {:error, {:replace_default_handler, other}, state}
        end

      {:error, {:not_found, @default_handler_id}} ->
        {:ok, state}

      other ->
        {:error, {:read_default_handler, other}, state}
    end
  end

  defp sync_default_handler(%{default_handler_config: nil} = state, false), do: {:ok, state}

  defp sync_default_handler(%{default_handler_config: config} = state, false) do
    case restore_default_handler(config) do
      :ok -> {:ok, %{state | default_handler_config: nil}}
      other -> {:error, {:restore_default_handler, other}, state}
    end
  end

  defp remove_unused_handler(state, true), do: {:ok, state}
  defp remove_unused_handler(%{handler_installed?: false} = state, false), do: {:ok, state}

  defp remove_unused_handler(state, false) do
    case Breeze.Logger.Handler.remove() do
      :ok -> {:ok, %{state | handler_installed?: false}}
      other -> {:error, {:remove_handler, other}, state}
    end
  end

  defp restore_default_handler(nil), do: :ok

  defp restore_default_handler(config) do
    :logger.set_handler_config(@default_handler_id, config)
  end

  defp effective_max_entries(%{configurations: configurations}) do
    configurations
    |> Map.values()
    |> Enum.map(& &1.max_entries)
    |> Enum.max(fn -> @default_max_entries end)
  end

  defp put_entry(entries, entry_count, entry, max_entries) do
    entry
    |> :queue.in(entries)
    |> trim_entries(entry_count + 1, max_entries)
  end

  defp trim_entries(entries, entry_count, max_entries) when entry_count > max_entries do
    {{:value, _entry}, entries} = :queue.out(entries)
    trim_entries(entries, entry_count - 1, max_entries)
  end

  defp trim_entries(entries, entry_count, _max_entries), do: {entries, entry_count}

  defp entries_to_list(%{entries: entries}), do: :queue.to_list(entries)

  defp reject_monitor(entries, ref) do
    entries
    |> Enum.reject(fn {_pid, entry} -> entry.ref == ref end)
    |> Map.new()
  end

  defp demonitor(%{ref: ref}) when is_reference(ref), do: Process.demonitor(ref, [:flush])
  defp demonitor(_entry), do: :ok

  defp normalize_config(false), do: {:ok, :disabled}
  defp normalize_config(nil), do: {:ok, :disabled}
  defp normalize_config(true), do: normalize_config(:attach)
  defp normalize_config(mode) when mode in [:attach, :replace], do: normalize_config(mode: mode)

  defp normalize_config(opts) when is_list(opts) do
    mode = Keyword.get(opts, :mode, :attach)
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)

    cond do
      mode not in [:attach, :replace] ->
        {:error, {:invalid_logger_mode, mode}}

      not (is_integer(max_entries) and max_entries > 0) ->
        {:error, {:invalid_max_entries, max_entries}}

      true ->
        {:ok,
         %{
           mode: mode,
           max_entries: max_entries,
           remote_inspector?: false,
           view: nil
         }}
    end
  end

  defp normalize_config(config), do: {:error, {:invalid_logger_config, config}}

  defp normalize_entry(%{} = entry) do
    %{
      level: Map.get(entry, :level, :info),
      line: entry |> Map.get(:line, inspect(entry)) |> to_string()
    }
  end

  defp normalize_entry(entry), do: %{level: :info, line: inspect(entry)}

  defp maybe_publish_logs(state) do
    case remote_inspector_view(state) do
      nil -> :ok
      view -> Breeze.RemoteInspector.publish_logs(entries_to_list(state), view: view)
    end
  end

  defp maybe_publish_log_entry(state, entry) do
    case remote_inspector_view(state) do
      nil -> :ok
      view -> Breeze.RemoteInspector.publish_log_entry(entry, view: view)
    end
  end

  defp remote_inspector_view(state) do
    Enum.find_value(state.configurations, fn {_pid, config} ->
      if config.remote_inspector?, do: config.view
    end)
  end

  defp call(message) do
    case Process.whereis(@name) do
      pid when is_pid(pid) -> GenServer.call(pid, message)
      nil -> {:error, :not_started}
    end
  catch
    :exit, reason when reason in [:noproc, :normal, :shutdown] ->
      {:error, :not_started}

    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] ->
      {:error, :not_started}
  end
end
