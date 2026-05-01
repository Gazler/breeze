defmodule Breeze.Server.Debug do
  @moduledoc false

  @window_size 20
  @rate_window_ms 1_000

  def snapshot(state) do
    state.debug.stats
    |> Map.put(:focused, state.focused)
    |> Map.put(:pending?, not is_nil(state.input.pending_ref))
    |> Map.put(:screen, state.terminal.size)
  end

  def put_stat(state, key, value) do
    state
    |> update_stats(&Map.put(&1, key, value))
    |> maybe_record_sample(key, value)
    |> schedule_push()
  end

  def increment_stat(state, key) do
    now = System.monotonic_time(:millisecond)

    state
    |> update_stats(fn stats ->
      Map.update(stats, key, 1, fn value -> value + 1 end)
    end)
    |> update_rate(key, now)
    |> schedule_push()
  end

  def push_now(state) do
    stats = snapshot(state)

    Enum.each(state.debug.subscribers, fn subscriber ->
      if is_pid(subscriber) and Process.alive?(subscriber) do
        send(subscriber, {:debug_stats, stats})
      end
    end)

    state
  end

  def schedule_push(%{debug: %{push_timer: nil, push_interval_ms: interval}} = state) do
    update_debug(state, push_timer: Process.send_after(self(), :debug_push, interval))
  end

  def schedule_push(state), do: state

  defp update_stats(state, fun), do: update_debug(state, stats: fun.(state.debug.stats))

  defp update_debug(state, updates), do: %{state | debug: struct!(state.debug, updates)}

  def sum_timing_us(child_timings) do
    Enum.reduce(child_timings, 0, fn %{us: us}, acc -> acc + us end)
  end

  def debug_live_child_us(child_timings) do
    child_timings
    |> Enum.filter(&debug_child_timing?/1)
    |> sum_timing_us()
  end

  def non_debug_child_timings(child_timings) do
    Enum.reject(child_timings, &debug_child_timing?/1)
  end

  def normalize_child_timings(child_timings) do
    child_timings
    |> Enum.sort_by(& &1.us, :desc)
    |> Enum.take(5)
    |> Enum.map(fn timing ->
      timing
      |> Map.update!(:view, &inspect/1)
    end)
  end

  def summarize_profile(entries) do
    entries
    |> Enum.filter(fn entry ->
      entry.metric in [
        :view_render_us,
        :template_tree_us,
        :build_tree_us,
        :layout_us,
        :render_with_dimensions_us,
        :item_render_us,
        :compose_us,
        :render_children_us,
        :container_render_self_us,
        :container_layer_map_us,
        :layer_maps_to_content_us
      ]
    end)
    |> Enum.take(6)
    |> Enum.map(fn %{label: label, metric: metric, value: value} ->
      %{label: shorten_label(label), metric: metric, value: value}
    end)
  end

  def put_child_patch_stats(state, %{child_id: "debug"}, _fragment, _composed, _written) do
    state
  end

  def put_child_patch_stats(state, ctx, fragment, composed_at, written_at) do
    total_us = written_at - ctx.started_at
    write_us = written_at - composed_at
    profile_entries = Breeze.DebugProfiler.snapshot(ctx.profile_scope)

    state
    |> put_stat(:last_render_cause, :child_patch)
    |> put_stat(:last_root_snapshot_us, 0)
    |> put_stat(:last_root_snapshot_app_us, 0)
    |> put_stat(:last_live_children_us, ctx.child_render_us)
    |> put_stat(:last_live_children_app_us, ctx.child_render_us)
    |> put_stat(
      :last_live_children,
      normalize_child_timings([%{id: ctx.child_id, view: ctx.view, us: ctx.child_render_us}])
    )
    |> put_stat(:last_render_profile, summarize_profile(profile_entries))
    |> put_stat(:last_reconcile_passes, 1)
    |> put_stat(:last_reconcile_changed_ids, [ctx.child_id])
    |> put_stat(:last_prepare_decorations_us, 0)
    |> put_stat(:last_render_base_us, total_us)
    |> put_stat(:last_render_base_app_us, total_us)
    |> put_stat(:last_frame_compose_us, composed_at - ctx.started_at)
    |> put_stat(:last_terminal_write_us, write_us)
    |> put_stat(:last_frame_us, total_us)
    |> put_stat(:last_frame_bytes, byte_size(fragment))
    |> put_stat(:overlay_count, 0)
  end

  defp maybe_record_sample(state, key, value) when is_integer(value) do
    if tracked_timing_key?(key) do
      state
      |> update_history(key, value)
      |> update_summary(key)
    else
      state
    end
  end

  defp maybe_record_sample(state, _key, _value), do: state

  defp debug_child_timing?(%{id: "debug"}), do: true
  defp debug_child_timing?(_timing), do: false

  defp tracked_timing_key?(key) do
    key in [
      :last_root_snapshot_app_us,
      :last_live_children_app_us,
      :last_render_base_app_us,
      :last_prepare_decorations_us,
      :last_frame_compose_us,
      :last_terminal_write_us,
      :last_frame_us,
      :last_animation_us
    ]
  end

  defp update_history(state, key, value) do
    history_key = {:history, key}

    update_in(state.debug.stats, fn stats ->
      history =
        stats
        |> Map.get(history_key, [])
        |> Kernel.++([value])
        |> Enum.take(-@window_size)

      Map.put(stats, history_key, history)
    end)
  end

  defp update_summary(state, key) do
    history_key = {:history, key}
    avg_key = {:avg, key}
    max_key = {:max, key}

    update_in(state.debug.stats, fn stats ->
      history = Map.get(stats, history_key, [])

      if history == [] do
        stats
      else
        avg = div(Enum.sum(history), length(history))
        max_value = Enum.max(history)

        stats
        |> Map.put(avg_key, avg)
        |> Map.put(max_key, max_value)
      end
    end)
  end

  defp update_rate(state, key, now) do
    rate_key = {:rate, key}

    update_in(state.debug.stats, fn stats ->
      timestamps =
        stats
        |> Map.get({:rate_window, key}, [])
        |> Kernel.++([now])
        |> Enum.filter(fn timestamp -> now - timestamp <= @rate_window_ms end)

      stats
      |> Map.put({:rate_window, key}, timestamps)
      |> Map.put(rate_key, length(timestamps))
    end)
  end

  defp shorten_label(label) when is_binary(label) do
    if String.length(label) > 28 do
      String.slice(label, 0, 28)
    else
      label
    end
  end
end
