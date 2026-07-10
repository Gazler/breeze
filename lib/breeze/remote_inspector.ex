defmodule Breeze.RemoteInspector do
  @moduledoc false

  alias __MODULE__.Server

  @group {__MODULE__, :servers}
  @app_group {__MODULE__, :apps}

  def group, do: @group
  def app_group, do: @app_group

  def server_pid do
    ensure_remote_server_pid() || local_server_pid()
  end

  def available? do
    is_pid(ensure_remote_server_pid())
  end

  def ensure_server do
    case local_server_pid() do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        case Server.start_link() do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} when is_pid(pid) -> {:ok, pid}
          other -> other
        end
    end
  end

  def ensure_app_distribution(opts \\ []) do
    opts
    |> Keyword.put_new_lazy(:name, fn -> default_distribution_name(:app, opts) end)
    |> ensure_distribution()
  end

  def ensure_inspector_distribution(opts \\ []) do
    opts
    |> Keyword.put_new(:name, :inspector)
    |> ensure_distribution()
  end

  def ensure_distribution(opts) when is_list(opts) do
    if Node.alive?() do
      :ok
    else
      name = opts |> Keyword.fetch!(:name) |> normalize_distribution_name()
      type = Keyword.get(opts, :type, Keyword.get(opts, :name_type, :shortnames))
      key = {__MODULE__, :distribution_attempt, name, type}

      case Process.get(key) do
        nil ->
          result = start_distribution(name, type)
          unless result == :ok, do: Process.put(key, result)
          result

        result ->
          result
      end
    end
  end

  def default_distribution_name(role, opts \\ [])

  def default_distribution_name(:inspector, _opts), do: :inspector

  def default_distribution_name(:app, opts) do
    opts
    |> Keyword.get(:view)
    |> application_for_module()
    |> case do
      app when is_atom(app) and not is_nil(app) -> app
      _ -> :app
    end
  end

  def register_app(pid) when is_pid(pid) do
    ensure_registry_started()
    :pg.join(@app_group, pid)
  end

  def app_members do
    ensure_registry_started()

    case :pg.get_members(@app_group) do
      members when is_list(members) -> members
      _ -> []
    end
  end

  def subscribe(subscriber) when is_pid(subscriber) do
    with {:ok, pid} <- ensure_server() do
      Server.subscribe(pid, subscriber)
    end
  end

  def snapshot do
    case server_pid() do
      pid when is_pid(pid) -> Server.snapshot(pid)
      _ -> %{snapshots: %{}, latest_source: nil, logs: %{}}
    end
  end

  def publish(%{enabled?: false}), do: :ok

  def publish(snapshot) when is_map(snapshot) do
    _ = ensure_app_distribution(view: Map.get(snapshot, :root_view))

    case ensure_remote_server_pid() do
      pid when is_pid(pid) ->
        Server.publish(pid, self(), snapshot)

      _ ->
        :ok
    end
  end

  def publish_logs(entries, opts \\ []) when is_list(entries) do
    _ = ensure_app_distribution(opts)

    case ensure_remote_server_pid() do
      pid when is_pid(pid) -> Server.publish_logs(pid, self(), entries)
      _ -> :ok
    end
  end

  def publish_log_entry(entry, opts \\ []) when is_map(entry) do
    _ = ensure_app_distribution(opts)

    case ensure_remote_server_pid() do
      pid when is_pid(pid) -> Server.publish_log_entry(pid, self(), entry)
      _ -> :ok
    end
  end

  def members do
    ensure_registry_started()

    case :pg.get_members(@group) do
      members when is_list(members) -> members
      _ -> []
    end
  end

  def local_server_pid do
    Process.whereis(Server) || Enum.find(members(), &(node(&1) == node()))
  end

  def remote_server_pid do
    Enum.find(members(), &(node(&1) != node()))
  end

  defp ensure_remote_server_pid do
    remote_server_pid() ||
      case maybe_connect_default_inspector_node() do
        true -> remote_server_pid()
        _ -> nil
      end
  end

  defp maybe_connect_default_inspector_node do
    case default_inspector_node(node()) do
      nil ->
        false

      target when target == node() ->
        false

      target ->
        Node.connect(target)
    end
  end

  defp default_inspector_node(current_node) when is_atom(current_node) do
    case Atom.to_string(current_node) do
      "nonode@nohost" ->
        nil

      name ->
        case String.split(name, "@", parts: 2) do
          [_node_name, host] when host != "" -> String.to_atom("inspector@" <> host)
          _ -> nil
        end
    end
  end

  defp application_for_module(module) when is_atom(module),
    do: Application.get_application(module)

  defp application_for_module(_module), do: nil

  defp normalize_distribution_name(name) when is_atom(name), do: name
  defp normalize_distribution_name(name) when is_binary(name), do: String.to_atom(name)

  defp start_distribution(name, type) do
    case Node.start(name, type) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def ensure_registry_started do
    case Process.whereis(:pg) do
      nil ->
        case :pg.start_link() do
          {:ok, pid} ->
            Process.unlink(pid)
            :ok

          {:error, {:already_started, _pid}} ->
            :ok
        end

      _pid ->
        :ok
    end
  end
end

defmodule Breeze.RemoteInspector.Server do
  @moduledoc false

  use GenServer

  @max_log_entries 1_000
  @max_log_bytes 2_000_000
  @max_log_entry_bytes 100_000
  @log_flush_interval 50

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def subscribe(pid, subscriber) do
    GenServer.cast(pid, {:subscribe, subscriber})
  end

  def publish(pid, source_pid, snapshot) do
    GenServer.cast(pid, {:snapshot, source_pid, snapshot})
  end

  def publish_logs(pid, source_pid, entries) do
    GenServer.cast(pid, {:logs, source_pid, entries})
  end

  def publish_log_entry(pid, source_pid, entry) do
    GenServer.cast(pid, {:log_entry, source_pid, entry})
  end

  def snapshot(pid) do
    GenServer.call(pid, :snapshot)
  end

  @impl true
  def init(_) do
    :ok = Breeze.RemoteInspector.ensure_registry_started()
    :ok = :pg.join(Breeze.RemoteInspector.group(), self())
    send(self(), :sync_apps)

    {:ok,
     %{
       snapshots: %{},
       latest_source: nil,
       logs: %{},
       dirty_logs: MapSet.new(),
       log_flush_ref: nil,
       subscribers: MapSet.new(),
       source_monitors: %{}
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, public_state(state), state}
  end

  @impl true
  def handle_cast({:subscribe, subscriber}, state) do
    if is_pid(subscriber), do: Process.monitor(subscriber)

    state =
      state
      |> Map.update!(:subscribers, &MapSet.put(&1, subscriber))
      |> push_state()

    {:noreply, state}
  end

  def handle_cast({:snapshot, source_pid, snapshot}, state) do
    source = %{pid: source_pid, node: node(source_pid)}

    entry = %{
      source: source,
      snapshot: snapshot,
      updated_at: System.system_time(:millisecond),
      alive?: true
    }

    key = source_key(source)

    state =
      state
      |> ensure_source_monitor(source_pid, key)
      |> put_in([:snapshots, key], entry)
      |> Map.put(:latest_source, key)
      |> push_state()

    {:noreply, state}
  end

  def handle_cast({:logs, source_pid, entries}, state) when is_pid(source_pid) do
    source = %{pid: source_pid, node: node(source_pid)}
    key = source_key(source)
    now = System.system_time(:millisecond)

    log_entry = %{
      source: source,
      entries: normalize_log_entries(entries),
      updated_at: now
    }

    state =
      state
      |> ensure_source_monitor(source_pid, key)
      |> put_in([:logs, key], log_entry)
      |> mark_log_dirty(key)

    {:noreply, state}
  end

  def handle_cast({:log_entry, source_pid, entry}, state)
      when is_pid(source_pid) and is_map(entry) do
    source = %{pid: source_pid, node: node(source_pid)}
    key = source_key(source)
    now = System.system_time(:millisecond)
    entry = normalize_log_entry(entry)

    state =
      state
      |> ensure_source_monitor(source_pid, key)
      |> update_in([:logs], fn logs ->
        current =
          Map.get(logs, key, %{source: source, entries: [], updated_at: now})

        entries = trim_log_entries(current.entries ++ [entry])
        Map.put(logs, key, %{current | source: source, entries: entries, updated_at: now})
      end)
      |> mark_log_dirty(key)

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_logs, state) do
    state =
      Enum.reduce(state.dirty_logs, state, fn key, acc ->
        case Map.fetch(acc.logs, key) do
          {:ok, log_entry} -> push_log_event(acc, {:snapshot, key, log_entry})
          :error -> acc
        end
      end)

    {:noreply, %{state | dirty_logs: MapSet.new(), log_flush_ref: nil}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    key = source_key(%{pid: pid, node: node(pid)})

    state =
      cond do
        Map.has_key?(state.snapshots, key) ->
          state
          |> put_in([:snapshots, key, :alive?], false)
          |> update_in([:source_monitors], &drop_source_monitor(&1, key))
          |> push_state()

        Map.has_key?(state.logs, key) ->
          state
          |> update_in([:logs], &Map.delete(&1, key))
          |> update_in([:dirty_logs], &MapSet.delete(&1, key))
          |> update_in([:source_monitors], &drop_source_monitor(&1, key))
          |> push_state()

        true ->
          state
          |> Map.update!(:subscribers, &MapSet.delete(&1, pid))
          |> update_snapshots(key)
          |> push_state()
      end

    {:noreply, state}
  end

  def handle_info(:sync_apps, state) do
    {:noreply, sync_apps(state)}
  end

  defp drop_source_monitor(monitors, key) do
    monitors
    |> Enum.reject(fn {_ref, monitored_key} -> monitored_key == key end)
    |> Map.new()
  end

  defp ensure_source_monitor(state, pid, key) do
    if Enum.any?(state.source_monitors, fn {_ref, monitored_key} -> monitored_key == key end) do
      state
    else
      ref = Process.monitor(pid)
      put_in(state, [:source_monitors, ref], key)
    end
  end

  defp update_snapshots(state, key) do
    snapshots = Map.delete(state.snapshots, key)

    latest_source =
      if state.latest_source == key, do: fallback_latest(snapshots), else: state.latest_source

    %{state | snapshots: snapshots, latest_source: latest_source}
  end

  defp fallback_latest(snapshots) do
    snapshots
    |> Enum.max_by(fn {_key, entry} -> entry.updated_at end, fn -> nil end)
    |> case do
      nil -> nil
      {key, _entry} -> key
    end
  end

  defp push_state(state) do
    payload = public_state(state)

    Enum.each(state.subscribers, fn subscriber ->
      if is_pid(subscriber) and Process.alive?(subscriber) do
        send(subscriber, {:remote_inspector, payload})
      end
    end)

    state
  end

  defp push_log_event(state, event) do
    Enum.each(state.subscribers, fn subscriber ->
      if is_pid(subscriber) and Process.alive?(subscriber) do
        send(subscriber, {:remote_inspector_logs, event})
      end
    end)

    state
  end

  defp mark_log_dirty(%{log_flush_ref: nil} = state, key) do
    ref = Process.send_after(self(), :flush_logs, @log_flush_interval)
    %{state | dirty_logs: MapSet.put(state.dirty_logs, key), log_flush_ref: ref}
  end

  defp mark_log_dirty(state, key) do
    %{state | dirty_logs: MapSet.put(state.dirty_logs, key)}
  end

  defp sync_apps(state) do
    Enum.reduce(Breeze.RemoteInspector.app_members(), state, fn pid, acc ->
      if is_pid(pid) and pid != self() do
        case safe_snapshot(pid) do
          nil ->
            acc

          snapshot ->
            source = %{pid: pid, node: node(pid)}

            entry = %{
              source: source,
              snapshot: snapshot,
              updated_at: System.system_time(:millisecond),
              alive?: true
            }

            key = source_key(source)

            acc
            |> ensure_source_monitor(pid, key)
            |> put_in([:snapshots, key], entry)
            |> Map.put(:latest_source, key)
        end
      else
        acc
      end
    end)
    |> push_state()
  end

  defp safe_snapshot(pid) do
    Breeze.Server.inspector_snapshot(pid)
  catch
    :exit, _reason -> nil
  end

  defp public_state(state) do
    %{
      snapshots: state.snapshots,
      latest_source: state.latest_source,
      logs: state.logs
    }
  end

  defp source_key(%{node: node, pid: pid}), do: {node, inspect(pid)}

  defp normalize_log_entries(entries) do
    entries
    |> Enum.map(&normalize_log_entry/1)
    |> trim_log_entries()
  end

  defp normalize_log_entry(%{} = entry) do
    %{
      level: Map.get(entry, :level, :info),
      line: entry |> Map.get(:line, inspect(entry)) |> to_string() |> truncate_log_entry()
    }
  end

  defp normalize_log_entry(entry), do: %{level: :info, line: inspect(entry)}

  defp truncate_log_entry(line) when byte_size(line) <= @max_log_entry_bytes, do: line

  defp truncate_log_entry(line) do
    suffix = "\n... [log entry truncated]"
    keep = max(@max_log_entry_bytes - byte_size(suffix), 0)

    line
    |> binary_part(0, keep)
    |> String.replace_invalid()
    |> Kernel.<>(suffix)
  end

  defp trim_log_entries(entries) do
    entries
    |> Enum.take(-@max_log_entries)
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn entry, {kept, bytes} ->
      entry_bytes = byte_size(entry.line)

      if kept == [] or bytes + entry_bytes <= @max_log_bytes do
        {:cont, {[entry | kept], bytes + entry_bytes}}
      else
        {:halt, {kept, bytes}}
      end
    end)
    |> elem(0)
  end
end
