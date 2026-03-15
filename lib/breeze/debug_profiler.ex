defmodule Breeze.DebugProfiler do
  @moduledoc false

  @metric_event [:breeze, :render, :metric]
  @span_event [:breeze, :render]
  @handler_id "breeze-debug-profiler"
  @table :breeze_debug_profile

  def reset(scope) do
    ensure_table()
    ensure_handler()

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

    :ok
  end

  def snapshot(scope) do
    ensure_table()
    ensure_handler()

    :ets.match_object(@table, {{scope, :_, :_}, :_})
    |> Enum.map(fn {{^scope, label, metric}, value} ->
      %{label: label, metric: metric, value: value}
    end)
    |> Enum.sort_by(fn %{value: value} -> sort_value(value) end, :desc)
  end

  defp ensure_handler do
    case :telemetry.list_handlers(@metric_event) do
      [] ->
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

      _handlers ->
        :ok
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @table
        end

      _tid ->
        @table
    end
  end

  def handle_event(
        @metric_event,
        %{value: value},
        %{scope: scope, label: label, metric: metric},
        _config
      ) do
    ensure_table()
    :ets.insert(@table, {{scope, label, metric}, value})
    :ok
  end

  def handle_event(
        @span_event ++ [:stop],
        %{duration: duration},
        %{scope: scope, label: label, metric: metric},
        _config
      ) do
    ensure_table()
    value = System.convert_time_unit(duration, :native, :microsecond)
    :ets.insert(@table, {{scope, label, metric}, value})
    :ok
  end

  defp sort_value(value) when is_integer(value), do: value
  defp sort_value(_value), do: -1
end
