defmodule Breeze.RemoteInspector.Logs do
  @moduledoc false

  use Breeze.View
  import Breeze.Blocks

  alias BackBreeze.VirtualText.Source, as: VirtualTextSource

  attr :scroll_id, :string, required: true
  attr :source_text, :string, required: true
  attr :status_text, :string, required: true
  attr :line_count, :integer, required: true
  attr :content, :any, required: true

  def logs_tab(assigns) do
    ~H"""
    <.scroll id={@scroll_id} class="width-full height-full" scroll-autoscroll="bottom">
      <box class="width-full">
        <box class="width-full text-muted">source={@source_text}</box>
        <box class="width-full text-muted">logs={@status_text}</box>
        <box class="width-full">
        </box>
        <box :if={@line_count == 0} class="width-full text-muted">
          No logs captured for this source.
        </box>
        <box :if={@line_count > 0} class="width-full">{@content}</box>
      </box>
    </.scroll>
    """
  end

  def build_sources(logs, previous \\ %{}) do
    logs = logs || %{}

    logs
    |> Enum.map(fn {source, log_entry} ->
      signature = log_signature(log_entry)

      source_entry =
        case Map.get(previous || %{}, source) do
          %{signature: ^signature} = existing -> existing
          _ -> build_source(source, log_entry, signature)
        end

      {source, source_entry}
    end)
    |> Map.new()
  end

  def source(logs, active_source) do
    node = source_node(active_source)

    logs
    |> Kernel.||(%{})
    |> Enum.filter(fn {_key, entry} -> get_in(entry, [:source, :node]) == node end)
    |> Enum.max_by(fn {_key, entry} -> Map.get(entry, :updated_at, 0) end, fn -> nil end)
    |> case do
      {key, _entry} -> key
      nil -> latest_source(logs)
    end
  end

  def count(_logs, nil), do: 0

  def count(logs, source) do
    logs
    |> log_entries(source)
    |> length()
  end

  def status_line(_logs, nil, _now), do: "-"

  def status_line(logs, source, now) do
    case Map.get(logs || %{}, source) do
      %{entries: entries, updated_at: updated_at} when is_list(entries) ->
        "entries=#{length(entries)} updated=#{updated_at} age=#{age_text(now, updated_at)}"

      _ ->
        "-"
    end
  end

  def source_text(_logs, nil), do: "-"

  def source_text(logs, source) do
    case get_in(logs || %{}, [source, :source]) do
      %{node: node, pid: pid} -> "#{node} #{inspect(pid)}"
      _ -> "-"
    end
  end

  def content(_sources, nil), do: nil

  def content(sources, source) do
    case Map.get(sources || %{}, source) do
      nil ->
        nil

      log_source ->
        VirtualTextSource.lazy(
          cache_key: {:remote_inspector_logs, source, log_source.signature},
          cache?: false,
          intrinsic_width: max(log_source.intrinsic_width, 1),
          line_count_fn: fn width -> wrapped_line_count(log_source, width) end,
          slice_fn: fn start_line, visible_count, width ->
            slice(log_source, start_line, visible_count, width)
          end
        )
    end
  end

  def append(logs, key, source, entry, updated_at) do
    current = Map.get(logs || %{}, key, %{source: source, entries: [], updated_at: updated_at})
    entries = Enum.take(current.entries ++ [entry], -1_000)

    Map.put(logs || %{}, key, %{
      current
      | source: source,
        entries: entries,
        updated_at: updated_at
    })
  end

  defp latest_source(logs) do
    logs
    |> Kernel.||(%{})
    |> Enum.max_by(fn {_key, entry} -> Map.get(entry, :updated_at, 0) end, fn -> nil end)
    |> case do
      {key, _entry} -> key
      nil -> nil
    end
  end

  defp source_node({node, _pid}), do: node
  defp source_node(_source), do: nil

  defp log_signature(%{entries: entries, updated_at: updated_at}) when is_list(entries) do
    {length(entries), updated_at}
  end

  defp log_signature(_entry), do: {0, nil}

  defp build_source(source, log_entry, signature) do
    rows =
      log_entry
      |> Map.get(:entries, [])
      |> Enum.flat_map(&entry_rows/1)

    widths = Enum.map(rows, & &1.width)

    %{
      source: source,
      signature: signature,
      rows: List.to_tuple(rows),
      widths: List.to_tuple(widths),
      line_count: length(rows),
      intrinsic_width: Enum.max(widths, fn -> 1 end)
    }
  end

  defp entry_rows(%{} = entry) do
    style = entry |> Map.get(:level, :info) |> log_level_style()

    entry
    |> log_line()
    |> String.split("\n", trim: false)
    |> Enum.map(&build_row(&1, style))
  end

  defp entry_rows(entry), do: [build_row(inspect(entry), %{foreground_color: 8})]

  defp build_row(line, base_style) do
    chunks = parse_ansi_chunks(line)
    width = Enum.reduce(chunks, 0, fn %{width: width}, acc -> acc + width end)
    %{chunks: chunks, width: width, base_style: base_style}
  end

  defp log_entries(logs, source) do
    logs
    |> Kernel.||(%{})
    |> Map.get(source, %{})
    |> Map.get(:entries, [])
  end

  defp log_line(%{} = entry), do: Map.get(entry, :line, inspect(entry)) |> to_string()

  defp wrapped_line_count(%{intrinsic_width: intrinsic_width, line_count: line_count}, width)
       when is_integer(width) and width >= intrinsic_width do
    max(line_count, 0)
  end

  defp wrapped_line_count(%{widths: widths}, width) do
    width = wrap_width(width)

    widths
    |> Tuple.to_list()
    |> Enum.reduce(0, fn row_width, acc ->
      acc + max(div(row_width + width - 1, width), 1)
    end)
  end

  defp slice(_source, _start_line, visible_count, _width) when visible_count <= 0, do: []

  defp slice(%{intrinsic_width: intrinsic_width, rows: rows}, start_line, visible_count, width)
       when is_integer(width) and width >= intrinsic_width do
    rows
    |> tuple_slice(start_line, visible_count)
    |> Enum.map(&row_segments/1)
  end

  defp slice(%{rows: rows, widths: widths}, start_line, visible_count, width) do
    width = wrap_width(width)

    if tuple_size(rows) == 0 do
      []
    else
      0..(tuple_size(rows) - 1)//1
      |> Enum.reduce_while({0, []}, fn index, {seen_count, visible_lines} ->
        row = elem(rows, index)
        row_count = elem(widths, index) |> wrapped_row_count(width)

        cond do
          seen_count + row_count <= start_line ->
            {:cont, {seen_count + row_count, visible_lines}}

          length(visible_lines) >= visible_count ->
            {:halt, {seen_count, visible_lines}}

          true ->
            skip_count = max(start_line - seen_count, 0)
            take_count = visible_count - length(visible_lines)

            next_lines =
              row
              |> wrap_row(width)
              |> Enum.drop(skip_count)
              |> Enum.take(take_count)

            visible_lines = visible_lines ++ next_lines

            if length(visible_lines) >= visible_count do
              {:halt, {seen_count + row_count, visible_lines}}
            else
              {:cont, {seen_count + row_count, visible_lines}}
            end
        end
      end)
      |> elem(1)
    end
  end

  defp tuple_slice(tuple, start, count) do
    tuple_size = tuple_size(tuple)
    start = max(start, 0)
    last = min(start + count - 1, tuple_size - 1)

    if count <= 0 or start > last do
      []
    else
      Enum.map(start..last, &elem(tuple, &1))
    end
  end

  defp wrapped_row_count(0, _width), do: 1
  defp wrapped_row_count(row_width, width), do: max(div(row_width + width - 1, width), 1)

  defp wrap_width(width) when is_integer(width) and width > 0, do: width
  defp wrap_width(_width), do: 1

  defp row_segments(%{chunks: chunks, base_style: base_style}) do
    chunks
    |> Enum.reduce([], fn chunk, acc ->
      add_segment(acc, chunk.text, merge_log_style(base_style, chunk.style))
    end)
    |> Enum.reverse()
  end

  defp wrap_row(%{width: 0} = row, _width), do: [row_segments(row)]

  defp wrap_row(%{width: row_width} = row, width) when row_width <= width do
    [row_segments(row)]
  end

  defp wrap_row(%{chunks: chunks, base_style: base_style}, width) do
    {lines, current, _current_width} =
      Enum.reduce(chunks, {[], [], 0}, fn chunk, acc ->
        wrap_chunk(chunk, merge_log_style(base_style, chunk.style), width, acc)
      end)

    lines = if current == [], do: lines, else: [Enum.reverse(current) | lines]
    Enum.reverse(lines)
  end

  defp wrap_chunk(%{text: text}, style, width, acc) do
    text
    |> String.graphemes()
    |> Enum.reduce(acc, fn grapheme, {lines, current, current_width} ->
      grapheme_width = BackBreeze.Utils.string_length(grapheme)

      cond do
        current_width == 0 and grapheme_width > width ->
          {[[{grapheme, style}] | lines], [], 0}

        current_width > 0 and current_width + grapheme_width > width ->
          {[Enum.reverse(current) | lines], [{grapheme, style}], grapheme_width}

        true ->
          {lines, add_segment(current, grapheme, style), current_width + grapheme_width}
      end
    end)
  end

  defp add_segment(segments, "", _style), do: segments

  defp add_segment([{text, style} | rest], next_text, style) do
    [{text <> next_text, style} | rest]
  end

  defp add_segment(segments, text, style), do: [{text, style} | segments]

  defp merge_log_style(base, overrides), do: Map.merge(base, overrides)

  defp parse_ansi_chunks(line), do: parse_ansi_chunks(line, %{}, [])

  defp parse_ansi_chunks("", _style, chunks), do: Enum.reverse(chunks)

  defp parse_ansi_chunks(<<"\e[", rest::binary>>, style, chunks) do
    case :binary.match(rest, "m") do
      {index, 1} ->
        <<params::binary-size(^index), "m", rest::binary>> = rest
        parse_ansi_chunks(rest, apply_sgr(style, params), chunks)

      :nomatch ->
        parse_text_chunk(<<"\e[", rest::binary>>, style, chunks)
    end
  end

  defp parse_ansi_chunks(line, style, chunks), do: parse_text_chunk(line, style, chunks)

  defp parse_text_chunk(line, style, chunks) do
    case :binary.match(line, "\e[") do
      {0, 2} ->
        parse_ansi_chunks(line, style, chunks)

      {index, 2} ->
        <<text::binary-size(^index), rest::binary>> = line
        parse_ansi_chunks(rest, style, add_text_chunk(chunks, text, style))

      :nomatch ->
        parse_ansi_chunks("", style, add_text_chunk(chunks, line, style))
    end
  end

  defp add_text_chunk(chunks, "", _style), do: chunks

  defp add_text_chunk([%{style: style, text: text, width: width} | rest], next_text, style) do
    [
      %{
        text: text <> next_text,
        width: width + BackBreeze.Utils.string_length(next_text),
        style: style
      }
      | rest
    ]
  end

  defp add_text_chunk(chunks, text, style) do
    [%{text: text, width: BackBreeze.Utils.string_length(text), style: style} | chunks]
  end

  defp apply_sgr(style, params) do
    params
    |> sgr_params()
    |> apply_sgr_params(style)
  end

  defp sgr_params(""), do: [0]

  defp sgr_params(params) do
    params
    |> String.split(";")
    |> Enum.map(fn
      "" ->
        0

      param ->
        case Integer.parse(param) do
          {int, ""} -> int
          _ -> 0
        end
    end)
  end

  defp apply_sgr_params([], style), do: style
  defp apply_sgr_params([0 | rest], _style), do: apply_sgr_params(rest, %{})

  defp apply_sgr_params([1 | rest], style),
    do: apply_sgr_params(rest, Map.put(style, :bold, true))

  defp apply_sgr_params([3 | rest], style),
    do: apply_sgr_params(rest, Map.put(style, :italic, true))

  defp apply_sgr_params([22 | rest], style), do: apply_sgr_params(rest, Map.delete(style, :bold))

  defp apply_sgr_params([23 | rest], style),
    do: apply_sgr_params(rest, Map.delete(style, :italic))

  defp apply_sgr_params([39 | rest], style),
    do: apply_sgr_params(rest, Map.delete(style, :foreground_color))

  defp apply_sgr_params([49 | rest], style),
    do: apply_sgr_params(rest, Map.delete(style, :background_color))

  defp apply_sgr_params([foreground | rest], style) when foreground in 30..37 do
    apply_sgr_params(rest, Map.put(style, :foreground_color, foreground - 30))
  end

  defp apply_sgr_params([foreground | rest], style) when foreground in 90..97 do
    apply_sgr_params(rest, Map.put(style, :foreground_color, foreground - 90 + 8))
  end

  defp apply_sgr_params([background | rest], style) when background in 40..47 do
    apply_sgr_params(rest, Map.put(style, :background_color, background - 40))
  end

  defp apply_sgr_params([background | rest], style) when background in 100..107 do
    apply_sgr_params(rest, Map.put(style, :background_color, background - 100 + 8))
  end

  defp apply_sgr_params([38, 5, color | rest], style) when color in 0..255 do
    apply_sgr_params(rest, Map.put(style, :foreground_color, color))
  end

  defp apply_sgr_params([48, 5, color | rest], style) when color in 0..255 do
    apply_sgr_params(rest, Map.put(style, :background_color, color))
  end

  defp apply_sgr_params([38, 2, r, g, b | rest], style)
       when r in 0..255 and g in 0..255 and b in 0..255 do
    apply_sgr_params(rest, Map.put(style, :foreground_color, {r, g, b}))
  end

  defp apply_sgr_params([48, 2, r, g, b | rest], style)
       when r in 0..255 and g in 0..255 and b in 0..255 do
    apply_sgr_params(rest, Map.put(style, :background_color, {r, g, b}))
  end

  defp apply_sgr_params([_unknown | rest], style), do: apply_sgr_params(rest, style)

  defp log_level_style(:debug), do: %{foreground_color: 6}
  defp log_level_style(level) when level in [:info, :notice], do: %{}
  defp log_level_style(:warning), do: %{foreground_color: 3}

  defp log_level_style(level) when level in [:error, :critical, :alert, :emergency],
    do: %{foreground_color: 1}

  defp log_level_style(_level), do: %{}

  defp age_text(now, timestamp) when is_integer(now) and is_integer(timestamp) do
    "#{max(now - timestamp, 0)}ms"
  end

  defp age_text(_now, _timestamp), do: "-"
end
