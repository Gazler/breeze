defmodule Breeze.Server.Timeline do
  @moduledoc false

  @default_limit 120
  @max_detail_chars 500

  def enabled?(%{inspector_state: %{config: config}}), do: enabled_config?(config)
  def enabled?(_state), do: false

  def enabled_config?(config) when is_list(config) do
    case Keyword.get(config, :timeline, false) do
      value when value in [false, nil] -> false
      _value -> true
    end
  end

  def enabled_config?(_config), do: false

  def normalize_selection(_state, selected) when selected in ["latest", ""], do: "latest"

  def normalize_selection(state, selected) when is_binary(selected) do
    if Enum.any?(timeline_entries(state), &(Integer.to_string(Map.get(&1, :id)) == selected)) do
      selected
    else
      "latest"
    end
  end

  def normalize_selection(_state, _selected), do: "latest"

  def historical_selection?(state), do: not is_nil(selected_entry(state))

  def display_frame(state, live_lines, live_overlays) do
    case selected_entry(state) do
      %{frame: %{lines: lines}} when is_list(lines) ->
        {normalize_display_lines(lines, state), []}

      _entry ->
        {live_lines, live_overlays}
    end
  end

  def mark_changed(state, kind, detail \\ %{}) do
    if enabled?(state) do
      append_pending(state, %{
        kind: kind,
        detail: detail_string(detail)
      })
    else
      state
    end
  end

  def record_snapshot(state, kind, detail \\ %{}, opts \\ []) do
    if enabled?(state) and timeline_pending(state) != [] do
      pending = timeline_pending(state)
      frame = Keyword.get(opts, :frame) || frame_snapshot(state)

      entry =
        state
        |> base_entry(entry_kind(kind, pending), entry_detail(detail, pending))
        |> Map.put(:changes, pending)
        |> Map.put(:frame, frame)
        |> Map.put(:snapshot, Breeze.Inspector.snapshot(state, timeline: false))

      state
      |> clear_pending()
      |> append_entry(entry)
    else
      state
    end
  end

  def snapshot(state) do
    entries = timeline_entries(state)

    %{
      enabled?: true,
      count: length(entries),
      next_id: timeline_next_id(state),
      selected_id: timeline_selected_id(state),
      frame: frame_snapshot(state),
      entries: entries
    }
  end

  defp base_entry(state, kind, detail) do
    %{
      id: timeline_next_id(state),
      kind: kind,
      at: System.system_time(:millisecond),
      monotonic_at: System.monotonic_time(:millisecond),
      detail: detail_string(detail)
    }
  end

  defp append_entry(state, entry) do
    inspector = Map.get(state, :inspector_state, %{})
    limit = timeline_limit(state)

    entries =
      inspector
      |> Map.get(:timeline_entries, [])
      |> Kernel.++([entry])
      |> Enum.take(-limit)

    inspector =
      inspector
      |> Map.put(:timeline_entries, entries)
      |> Map.put(:timeline_next_id, entry.id + 1)

    %{state | inspector_state: inspector}
  end

  defp append_pending(state, change) do
    update_inspector_field(state, :timeline_pending, fn pending ->
      pending
      |> Kernel.++([change])
      |> Enum.take(-20)
    end)
  end

  defp clear_pending(state) do
    update_inspector_field(state, :timeline_pending, fn _pending -> [] end)
  end

  defp update_inspector_field(state, field, fun) do
    inspector = Map.get(state, :inspector_state, %{})
    inspector = Map.put(inspector, field, fun.(Map.get(inspector, field, [])))
    %{state | inspector_state: inspector}
  end

  defp timeline_entries(%{inspector_state: inspector}) do
    Map.get(inspector, :timeline_entries, [])
  end

  defp timeline_entries(_state), do: []

  defp selected_entry(state) do
    selected = timeline_selected_id(state)

    if selected in [nil, "latest"] do
      nil
    else
      Enum.find(timeline_entries(state), &(Integer.to_string(Map.get(&1, :id)) == selected))
    end
  end

  defp timeline_selected_id(%{inspector_state: inspector}) do
    Map.get(inspector, :timeline_selected_id, "latest")
  end

  defp timeline_selected_id(_state), do: "latest"

  defp timeline_pending(%{inspector_state: inspector}) do
    Map.get(inspector, :timeline_pending, [])
  end

  defp timeline_pending(_state), do: []

  defp timeline_next_id(%{inspector_state: inspector}) do
    Map.get(inspector, :timeline_next_id, 1)
  end

  defp timeline_next_id(_state), do: 1

  defp timeline_limit(%{inspector_state: %{config: config}}) do
    config
    |> configured_limit()
    |> normalize_limit()
  end

  defp timeline_limit(_state), do: @default_limit

  defp frame_snapshot(%{frame: frame, terminal: terminal}) do
    screen = Map.get(terminal, :size, %{width: 0, height: 0})

    %{
      width: Map.get(screen, :width, 0),
      height: Map.get(screen, :height, 0),
      lines: frame_lines(frame, Map.get(screen, :height, 0))
    }
  end

  defp frame_snapshot(_state), do: %{width: 0, height: 0, lines: []}

  defp frame_lines(%{last_lines: lines}, height) when is_list(lines) do
    lines
    |> Enum.take(max(height, 0))
    |> Enum.map(fn
      line when is_binary(line) -> line
      _line -> ""
    end)
  end

  defp frame_lines(%{base_output: output}, height) when is_binary(output) do
    output
    |> String.split("\n")
    |> Enum.take(max(height, 0))
  end

  defp frame_lines(_frame, _height), do: []

  defp normalize_display_lines(lines, %{terminal: %{size: %{height: height}}}) do
    lines
    |> Enum.map(fn
      line when is_binary(line) -> line
      _line -> ""
    end)
    |> Kernel.++(List.duplicate("", max(height - length(lines), 0)))
    |> Enum.take(max(height, 0))
  end

  defp normalize_display_lines(lines, _state), do: lines

  defp configured_limit(config) when is_list(config) do
    case Keyword.get(config, :timeline) do
      opts when is_list(opts) -> Keyword.get(opts, :limit, @default_limit)
      limit when is_integer(limit) -> limit
      _ -> Keyword.get(config, :timeline_limit, @default_limit)
    end
  end

  defp configured_limit(_config), do: @default_limit

  defp normalize_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(1_000)
  defp normalize_limit(_limit), do: @default_limit

  defp detail_string(detail) when is_binary(detail) do
    truncate(detail)
  end

  defp detail_string(detail) do
    detail
    |> inspect(limit: 20, printable_limit: @max_detail_chars, pretty: false)
    |> truncate()
  end

  defp truncate(value) when byte_size(value) <= @max_detail_chars, do: value

  defp truncate(value) do
    value
    |> String.slice(0, @max_detail_chars)
    |> Kernel.<>("...")
  end

  defp entry_kind(kind, [%{kind: single_kind}]), do: single_kind || kind
  defp entry_kind(kind, _pending), do: kind

  defp entry_detail(detail, pending) do
    detail =
      case detail do
        detail when detail in [%{}, "", nil] -> nil
        detail -> detail_string(detail)
      end

    change_detail =
      pending
      |> Enum.map(fn
        %{kind: kind, detail: detail} -> "#{kind}: #{detail}"
        %{kind: kind} -> to_string(kind)
      end)
      |> Enum.join("; ")

    [detail, change_detail]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> truncate()
  end
end
