defmodule Breeze.RemoteInspector do
  @moduledoc false

  alias __MODULE__.Server

  @group {__MODULE__, :servers}
  @app_group {__MODULE__, :apps}
  @page_config_key :remote_inspector_pages
  @reserved_page_ids ~w(tree overview layout theme implicit timeline)

  def group, do: @group
  def app_group, do: @app_group
  def reserved_page_ids, do: @reserved_page_ids

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

  def pages do
    :breeze
    |> Application.get_env(@page_config_key, [])
    |> normalize_pages()
  end

  def normalize_pages(config) do
    config
    |> normalize_page_config_list()
    |> List.wrap()
    |> Enum.flat_map(&normalize_page/1)
    |> Enum.reject(&(&1.id in @reserved_page_ids))
    |> Enum.uniq_by(& &1.id)
  end

  def ensure_app_distribution(opts \\ []) do
    opts
    |> Keyword.put_new_lazy(:name, fn -> default_distribution_name(:app, opts) end)
    |> ensure_distribution()
  end

  defp normalize_page(module) when is_atom(module) do
    module
    |> module_page_config()
    |> page_attrs()
    |> Map.put(:module, module)
    |> normalize_page_from_attrs()
  end

  defp normalize_page({module, opts}) when is_atom(module) and (is_list(opts) or is_map(opts)) do
    module_attrs =
      module
      |> module_page_config()
      |> page_attrs()

    module_attrs
    |> Map.merge(page_attrs(opts))
    |> Map.put(:module, module)
    |> normalize_page_from_attrs()
  end

  defp normalize_page({id, label, module}) when is_atom(module) do
    %{id: id, label: label, module: module}
    |> normalize_page_from_attrs()
  end

  defp normalize_page(config) when is_list(config) or is_map(config) do
    config
    |> page_attrs()
    |> normalize_page_from_attrs()
  end

  defp normalize_page(_config), do: []

  defp normalize_page_config_list(config) when is_list(config) do
    if Keyword.keyword?(config) and Keyword.has_key?(config, :module) do
      [config]
    else
      config
    end
  end

  defp normalize_page_config_list(config), do: config

  defp normalize_page_from_attrs(%{module: module} = attrs) when is_atom(module) do
    if page_module?(module) do
      id =
        attrs
        |> Map.get(:id, default_page_id(module))
        |> normalize_page_id()

      label =
        attrs
        |> Map.get(:label, humanize_page_id(id))
        |> normalize_page_label()

      if id && label do
        config =
          attrs
          |> Map.get(:config, %{})
          |> page_attrs()
          |> Map.merge(Map.drop(attrs, [:id, :label, :module, :assigns, :config]))

        page = %{
          id: id,
          label: label,
          module: module,
          assigns: normalize_page_assigns(Map.get(attrs, :assigns, %{})),
          config: config
        }

        [page]
      else
        []
      end
    else
      []
    end
  end

  defp normalize_page_from_attrs(_attrs), do: []

  defp page_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :render, 1)
  end

  defp page_module?(_module), do: false

  defp module_page_config(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :page, 0) do
      module.page()
    else
      []
    end
  end

  defp page_attrs(config) when is_map(config) do
    config
    |> Enum.map(fn {key, value} -> {page_attr_key(key), value} end)
    |> Map.new()
  end

  defp page_attrs(config) when is_list(config) do
    if Keyword.keyword?(config) do
      config
      |> Enum.map(fn {key, value} -> {page_attr_key(key), value} end)
      |> Map.new()
    else
      %{}
    end
  end

  defp page_attrs(_config), do: %{}

  defp page_attr_key(key) when key in [:id, "id"], do: :id
  defp page_attr_key(key) when key in [:label, "label"], do: :label
  defp page_attr_key(key) when key in [:module, "module"], do: :module
  defp page_attr_key(key) when key in [:assigns, "assigns"], do: :assigns
  defp page_attr_key(key), do: key

  defp normalize_page_id(id) when is_atom(id), do: id |> Atom.to_string() |> normalize_page_id()

  defp normalize_page_id(id) when is_binary(id) do
    id
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
    |> String.trim("-")
    |> String.downcase()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_page_id(id), do: id |> to_string() |> normalize_page_id()

  defp normalize_page_label(label) when is_binary(label) do
    case String.trim(label) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_page_label(label), do: label |> to_string() |> normalize_page_label()

  defp normalize_page_assigns(assigns) when is_map(assigns), do: assigns

  defp normalize_page_assigns(assigns) when is_list(assigns) do
    if Keyword.keyword?(assigns), do: Map.new(assigns), else: %{}
  end

  defp normalize_page_assigns(_assigns), do: %{}

  defp default_page_id(module) do
    module
    |> Module.split()
    |> List.last()
    |> case do
      nil -> nil
      name -> Macro.underscore(name)
    end
  end

  defp humanize_page_id(nil), do: nil

  defp humanize_page_id(id) do
    id
    |> String.replace("-", "_")
    |> String.split("_", trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
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
      _ -> %{snapshots: %{}, latest_source: nil}
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
    local = Process.whereis(Server)

    Enum.find(members(), fn pid ->
      (not is_pid(local) or pid != local) and not local_process?(pid) and node(pid) != node()
    end)
  end

  defp local_process?(pid) when is_pid(pid) do
    not is_nil(:erlang.process_info(pid, :status))
  rescue
    ArgumentError -> false
  end

  defp local_process?(_pid), do: false

  defp ensure_remote_server_pid do
    remote_server_pid() ||
      case maybe_connect_default_inspector_node() do
        true -> remote_server_pid()
        _ -> nil
      end
  end

  defp maybe_connect_default_inspector_node do
    if test_env?() do
      false
    else
      case default_inspector_node(node()) do
        nil ->
          false

        target when target == node() ->
          false

        target ->
          Node.connect(target)
      end
    end
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  rescue
    _ -> false
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

  defp default_inspector_node(_current_node), do: nil

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

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def subscribe(pid, subscriber) do
    GenServer.cast(pid, {:subscribe, subscriber})
  end

  def publish(pid, source_pid, snapshot) do
    GenServer.cast(pid, {:snapshot, source_pid, snapshot})
  end

  def snapshot(pid) do
    GenServer.call(pid, :snapshot)
  end

  @impl true
  def init(_) do
    :ok = Breeze.RemoteInspector.ensure_registry_started()
    :ok = :pg.join(Breeze.RemoteInspector.group(), self())
    send(self(), :sync_apps)
    {:ok, %{snapshots: %{}, latest_source: nil, subscribers: MapSet.new(), source_monitors: %{}}}
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

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    key = source_key(%{pid: pid, node: node(pid)})

    state =
      if Map.has_key?(state.snapshots, key) do
        state
        |> put_in([:snapshots, key, :alive?], false)
        |> update_in([:source_monitors], &drop_source_monitor(&1, key))
        |> push_state()
      else
        key = source_key(%{pid: pid, node: node(pid)})

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
      latest_source: state.latest_source
    }
  end

  defp source_key(%{node: node, pid: pid}), do: {node, inspect(pid)}
end
