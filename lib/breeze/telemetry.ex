defmodule Breeze.Telemetry do
  @moduledoc false

  def span(event, metadata, fun) when is_function(fun, 0) do
    if enabled?() do
      :telemetry.span(event, metadata, fn ->
        result = fun.()
        {result, metadata}
      end)
    else
      fun.()
    end
  end

  def execute(event, measurements, metadata) do
    if enabled?() do
      :telemetry.execute(event, measurements, metadata)
    end

    :ok
  end

  def enabled? do
    not Application.get_env(:breeze, :disable_telemetry, false)
  end
end
