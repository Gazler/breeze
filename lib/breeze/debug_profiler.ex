defmodule Breeze.DebugProfiler do
  @moduledoc false

  @metric_event [:breeze, :render, :metric]
  @span_event [:breeze, :render]
  @handler_id "breeze-debug-profiler"
  @table :breeze_debug_profile

  def reset(scope) do
    if enabled?() do
      ensure_handler()
      delete_scope(scope)
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

  def enabled? do
    not Application.get_env(:breeze, :disable_telemetry, false)
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
    with_table(fn ->
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
    end)
  end

  defp insert_metric(scope, label, metric, value) do
    with_table(fn ->
      :ets.insert(@table, {{scope, label, metric}, value})
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

    __MODULE__.TableOwner.ensure_table(pid)
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

  @impl true
  def init(state) do
    ensure_table!()
    {:ok, state}
  end

  @impl true
  def handle_call(:ensure_table, _from, state) do
    ensure_table!()
    {:reply, :ok, state}
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
