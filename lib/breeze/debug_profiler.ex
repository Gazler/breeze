defmodule Breeze.DebugProfiler do
  @moduledoc false

  @metric_event [:breeze, :render, :metric]
  @span_event [:breeze, :render]
  @handler_id "breeze-debug-profiler"
  @table :breeze_debug_profile
  @tracked_table_owner_key {__MODULE__, :tracked_table_owner}

  def reset(scope) do
    if enabled?() do
      ensure_handler()
      delete_scope(scope)
      activate_scope(scope)
    end

    :ok
  end

  def snapshot(scope) do
    if enabled?() do
      ensure_handler()

      entries = match_scope(scope)
      delete_scope(scope)

      entries
      |> Enum.map(fn {{^scope, label, metric}, value} ->
        %{label: label, metric: metric, value: value}
      end)
      |> Enum.sort_by(fn %{value: value} -> sort_value(value) end, :desc)
    else
      []
    end
  end

  def discard(scope) do
    delete_scope(scope)
    :ok
  end

  def discard_owner(owner) when is_pid(owner) do
    with_table(fn ->
      @table
      |> :ets.match_object({{:active, :_}, owner})
      |> Enum.each(fn {{:active, scope}, ^owner} -> delete_scope_entries(scope) end)
    end)

    :ok
  end

  def enabled? do
    Breeze.Telemetry.enabled?() and
      not Application.get_env(:breeze, :disable_debug_profiler, false)
  end

  defp ensure_handler do
    handlers = :telemetry.list_handlers(@metric_event)

    if Enum.any?(handlers, &(&1.id == @handler_id)) do
      :ok
    else
      try do
        :telemetry.attach_many(
          @handler_id,
          [@metric_event, @span_event ++ [:stop]],
          &__MODULE__.handle_event/4,
          nil
        )
      rescue
        ArgumentError -> :ok
      end
    end
  end

  defp match_scope(scope) do
    with_table(fn ->
      :ets.match_object(@table, {{scope, :_, :_}, :_})
    end)
  end

  defp delete_scope(scope) do
    with_table(fn -> delete_scope_entries(scope) end)
  end

  defp delete_scope_entries(scope) do
    :ets.select_delete(
      @table,
      [
        {
          {{scope, :"$1", :"$2"}, :_},
          [],
          [true]
        }
      ]
    )

    :ets.delete(@table, {:active, scope})
  end

  defp activate_scope(scope) do
    track_scope_owner()

    with_table(fn ->
      :ets.insert(@table, {{:active, scope}, self()})
    end)
  end

  defp track_scope_owner do
    pid =
      case Process.whereis(__MODULE__.TableOwner) do
        nil -> ensure_table_owner()
        pid -> pid
      end

    unless Process.get(@tracked_table_owner_key) == pid do
      __MODULE__.TableOwner.track_owner(pid, self())
      Process.put(@tracked_table_owner_key, pid)
    end
  end

  defp insert_metric(scope, label, metric, value) do
    with_table(fn ->
      if :ets.member(@table, {:active, scope}) do
        :ets.insert(@table, {{scope, label, metric}, value})
      end
    end)

    :ok
  end

  defp with_table(fun) do
    ensure_table()

    try do
      fun.()
    rescue
      ArgumentError ->
        ensure_table_owner()
        fun.()
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        ensure_table_owner()
        :ok

      _tid ->
        :ok
    end
  end

  defp ensure_table_owner do
    pid =
      case Process.whereis(__MODULE__.TableOwner) do
        nil ->
          case __MODULE__.TableOwner.start() do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end

        pid ->
          pid
      end

    :ok = __MODULE__.TableOwner.ensure_table(pid)
    pid
  end

  def handle_event(
        @metric_event,
        %{value: value},
        %{scope: scope, label: label, metric: metric},
        _config
      ) do
    insert_metric(scope, label, metric, value)
  end

  def handle_event(
        @span_event ++ [:stop],
        %{duration: duration},
        %{scope: scope, label: label, metric: metric},
        _config
      ) do
    value = System.convert_time_unit(duration, :native, :microsecond)
    insert_metric(scope, label, metric, value)
  end

  defp sort_value(value) when is_integer(value), do: value
  defp sort_value(_value), do: -1
end

defmodule Breeze.DebugProfiler.TableOwner do
  @moduledoc false

  use GenServer

  @table :breeze_debug_profile

  def start do
    GenServer.start(__MODULE__, %{}, name: __MODULE__)
  end

  def ensure_table(pid) do
    GenServer.call(pid, :ensure_table)
  end

  def track_owner(pid, owner) do
    GenServer.cast(pid, {:track_owner, owner})
  end

  @impl true
  def init(_state) do
    ensure_table!()
    {:ok, %{owners: %{}, owners_by_ref: %{}}}
  end

  @impl true
  def handle_call(:ensure_table, _from, state) do
    ensure_table!()
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:track_owner, owner}, state) do
    if Map.has_key?(state.owners, owner) do
      {:noreply, state}
    else
      ref = Process.monitor(owner)

      {:noreply,
       %{
         state
         | owners: Map.put(state.owners, owner, ref),
           owners_by_ref: Map.put(state.owners_by_ref, ref, owner)
       }}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, owner, _reason}, state) do
    Breeze.DebugProfiler.discard_owner(owner)

    {:noreply,
     %{
       state
       | owners: Map.delete(state.owners, owner),
         owners_by_ref: Map.delete(state.owners_by_ref, ref)
     }}
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
