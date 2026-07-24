defmodule Breeze.Server.InputTest do
  use ExUnit.Case, async: true

  alias Breeze.Server.Input

  test "printable batching combines adjacent keys when opted in" do
    state = flush([{:key, "a"}, {:key, "b"}, {:key, "c"}], true)

    assert [{:key, %{"key" => "abc", "__batched_printable__" => true}}] =
             Enum.reverse(state.events)
  end

  test "printable input preserves adjacent repeated keys without batching opt-in" do
    state = flush([{:key, "w"}, {:key, "w"}, {:key, "a"}], false)

    assert ["w", "w", "a"] = event_keys(state.events)
  end

  test "already chunked printable input is split without batching opt-in" do
    state =
      flush(
        [{:key, %{"key" => "wwa", "__batched_printable__" => true}}],
        false
      )

    assert ["w", "w", "a"] = event_keys(state.events)
  end

  defp flush(input, batch?) do
    state = %{
      input: %{queued_input: :queue.from_list(input)},
      batch?: batch?,
      events: []
    }

    handlers = %{
      batchable_printable?: fn key, state ->
        state.batch? and Breeze.InputCapture.printable_key?(key)
      end,
      handle_sync_or_deferred: fn event, state ->
        {:noreply, update_in(state.events, &[event | &1])}
      end,
      handle_mouse: fn _event, state -> {:noreply, state} end,
      sync_message?: fn _event, _state -> true end
    }

    assert {:noreply, state} = Input.flush_batch(state, handlers)
    state
  end

  defp event_keys(events) do
    events
    |> Enum.reverse()
    |> Enum.map(fn
      {:key, %{"key" => key}} -> key
      {:key, key} -> key
    end)
  end
end
