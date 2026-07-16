defmodule Breeze.Server.Input do
  @moduledoc false

  @pipeline_defaults [
    pending_ref: nil,
    pending_started_at: nil,
    pending_sync_child_render_id: nil,
    queued_input: :queue.new(),
    flush_scheduled?: false,
    render_cause: nil,
    render_after_flush?: false,
    render_boundary?: false,
    render_timer: nil,
    render_timer_token: nil
  ]

  def reset_pipeline(state, overrides \\ []) do
    %{state | input: struct!(state.input, Keyword.merge(@pipeline_defaults, overrides))}
  end

  @mouse_modifier_keys ["shiftKey", "altKey", "ctrlKey"]

  def enqueue(state, decoded), do: update_in(state.input.queued_input, &:queue.in(decoded, &1))

  def schedule_flush(%{input: %{flush_scheduled?: true}} = state, _message), do: state
  def schedule_flush(%{input: %{queued_input: {[], []}}} = state, _message), do: state

  def schedule_flush(state, message) do
    send(self(), message)
    put_in(state.input.flush_scheduled?, true)
  end

  def flush_batch(state, handlers) do
    case queue_out(state.input.queued_input) do
      {:empty, _queue} ->
        {:noreply, state}

      {{:value, decoded}, queue} ->
        state = put_in(state.input.queued_input, queue)

        case process_batched_input(decoded, state, handlers) do
          {:stop, state} ->
            {:stop, state}

          {:noreply, state} ->
            continue_flushing_or_pause(state, handlers)
        end
    end
  end

  def key_name(%{"key" => key}) when is_binary(key), do: key
  def key_name(key) when is_binary(key), do: key
  def key_name(_), do: nil

  def raw_printable_key?(key) when is_binary(key) do
    Breeze.Printable.single_key?(key)
  end

  def raw_printable_key?(_key), do: false

  defp process_batched_input({:mouse, %{"button" => button} = event}, state, handlers)
       when button in ["wheel_down", "wheel_up"] do
    {event, state} = coalesce_wheel_events_from_queue(event, state, 1)
    handlers.handle_mouse.(event, state)
  end

  defp process_batched_input(
         {:key, %{"__batched_printable__" => true, "key" => key} = event},
         state,
         handlers
       )
       when is_binary(key) do
    if handlers.batchable_printable?.(event, state) do
      {key, state} = coalesce_printable_keys_from_queue(key, state, handlers)
      handlers.handle_sync_or_deferred.({:key, Map.put(event, "key", key)}, state)
    else
      state
      |> prepend_printable_keys(key)
      |> flush_batch(handlers)
    end
  end

  defp process_batched_input({:key, key}, state, handlers) do
    if handlers.batchable_printable?.(key, state) do
      {key, state} = coalesce_printable_keys_from_queue(key, state, handlers)
      handlers.handle_sync_or_deferred.({:key, batched_printable_event(key)}, state)
    else
      handlers.handle_sync_or_deferred.({:key, key}, state)
    end
  end

  defp process_batched_input(decoded, state, handlers) do
    handlers.handle_sync_or_deferred.(decoded, state)
  end

  defp continue_flushing_or_pause(state, handlers) do
    case queue_peek(state.input.queued_input) do
      {:value, next} ->
        if handlers.sync_message?.(next, state) do
          flush_batch(state, handlers)
        else
          {:noreply, state}
        end

      :empty ->
        {:noreply, state}
    end
  end

  defp coalesce_wheel_events_from_queue(event, state, repeat) do
    case queue_out(state.input.queued_input) do
      {{:value, {:mouse, %{"button" => button} = next_event}}, queue} ->
        if button == event["button"] and wheel_match?(event, next_event) do
          coalesce_wheel_events_from_queue(
            event,
            put_in(state.input.queued_input, queue),
            repeat + 1
          )
        else
          {Map.put(event, "repeat", repeat), state}
        end

      {{:value, _next}, _queue} ->
        {Map.put(event, "repeat", repeat), state}

      {:empty, _queue} ->
        {Map.put(event, "repeat", repeat), state}
    end
  end

  defp coalesce_printable_keys_from_queue(key, state, handlers) do
    case queue_out(state.input.queued_input) do
      {{:value, {:key, next_key}}, queue} ->
        if handlers.batchable_printable?.(next_key, state) do
          coalesce_printable_keys_from_queue(
            key <> printable_key_text(next_key),
            put_in(state.input.queued_input, queue),
            handlers
          )
        else
          {key, state}
        end

      {{:value, _next}, _queue} ->
        {key, state}

      {:empty, _queue} ->
        {key, state}
    end
  end

  defp prepend_printable_keys(state, key) do
    printable_keys =
      key
      |> String.graphemes()
      |> Enum.map(&{:key, &1})
      |> :queue.from_list()

    update_in(state.input.queued_input, &:queue.join(printable_keys, &1))
  end

  defp printable_key_text(%{"key" => key}) when is_binary(key), do: key
  defp printable_key_text(key) when is_binary(key), do: key

  defp wheel_match?(left, right) do
    left["action"] == right["action"] and left["x"] == right["x"] and
      left["y"] == right["y"] and mouse_modifiers_match?(left, right)
  end

  defp mouse_modifiers_match?(left, right) do
    Enum.all?(@mouse_modifier_keys, fn key ->
      modifier_active?(left, key) == modifier_active?(right, key)
    end)
  end

  defp modifier_active?(event, key), do: Map.get(event, key) in [true, "true"]

  defp queue_out(queue), do: :queue.out(queue)

  defp queue_peek(queue) do
    case :queue.peek(queue) do
      :empty -> :empty
      value -> {:value, value}
    end
  end

  defp batched_printable_event(key), do: %{"key" => key, "__batched_printable__" => true}
end
