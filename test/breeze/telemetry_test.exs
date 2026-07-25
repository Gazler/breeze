defmodule Breeze.TelemetryTest do
  use ExUnit.Case, async: false

  @event [:breeze, :telemetry_test]

  setup do
    previous = Application.get_env(:breeze, :disable_telemetry, :unset)
    handler_id = "breeze-telemetry-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [@event ++ [:start], @event ++ [:stop], @event],
        &__MODULE__.handle_event/4,
        self()
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)

      case previous do
        :unset -> Application.delete_env(:breeze, :disable_telemetry)
        value -> Application.put_env(:breeze, :disable_telemetry, value)
      end
    end)

    :ok
  end

  test "span emits telemetry and returns the wrapped result" do
    Application.delete_env(:breeze, :disable_telemetry)

    assert :result = Breeze.Telemetry.span(@event, %{source: :test}, fn -> :result end)
    assert_receive {[:breeze, :telemetry_test, :start], %{}, %{source: :test}}
    assert_receive {[:breeze, :telemetry_test, :stop], %{duration: duration}, %{source: :test}}
    assert is_integer(duration)
  end

  test "disabled telemetry executes the function without emitting events" do
    Application.put_env(:breeze, :disable_telemetry, true)

    assert :result = Breeze.Telemetry.span(@event, %{source: :test}, fn -> :result end)
    assert :ok = Breeze.Telemetry.execute(@event, %{value: 1}, %{source: :test})
    refute_received _event
  end

  def handle_event(event, measurements, metadata, pid) do
    send(pid, {event, measurements, metadata})
  end
end
