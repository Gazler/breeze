defmodule Breeze.Server.Frame do
  @moduledoc false

  alias BackBreeze.Box.LayerMap

  def normalize_lines(output, screen_height) do
    output
    |> :binary.split("\n", [:global])
    |> then(fn lines ->
      lines = if lines == [], do: [""], else: lines
      lines ++ List.duplicate("", max(screen_height - length(lines), 0))
    end)
    |> Enum.take(screen_height)
  end

  def build_payload(nil, lines, _prev_overlays, overlays, screen_width) do
    full_redraw_payload(lines, overlays, screen_width)
  end

  def build_payload(prev_lines, lines, prev_overlays, overlays, screen_width) do
    changed_base_rows = changed_base_rows(prev_lines, lines)
    changed_overlay_rows = changed_overlay_rows(prev_overlays, overlays)

    patch_only_overlay_rows =
      patch_only_overlay_rows(prev_overlays, overlays, changed_overlay_rows)

    repaired_overlay_rows = MapSet.difference(changed_overlay_rows, patch_only_overlay_rows)
    changed_rows = MapSet.union(changed_base_rows, changed_overlay_rows)

    if MapSet.size(changed_rows) == 0 do
      ""
    else
      IO.iodata_to_binary([
        row_patch_payload(
          lines,
          MapSet.union(changed_base_rows, repaired_overlay_rows),
          screen_width
        ),
        overlay_patch_payload(overlays, changed_rows)
      ])
    end
  end

  def patch_lines(
        lines,
        fragment,
        %{left: left, top: top, width: width, height: height},
        screen_width
      )
      when is_list(lines) and is_binary(fragment) and is_integer(left) and left >= 0 and
             is_integer(top) and top >= 0 and is_integer(width) and width > 0 and
             is_integer(height) and height > 0 and is_integer(screen_width) and
             screen_width > 0 do
    patch_width = min(width, max(screen_width - left, 0))

    if patch_width == 0 do
      lines
    else
      fragment
      |> normalize_lines(height)
      |> Enum.with_index()
      |> Enum.reduce(lines, fn {fragment_line, row_offset}, acc ->
        row = top + row_offset

        if row < length(acc) do
          List.replace_at(
            acc,
            row,
            patch_line(Enum.at(acc, row, ""), fragment_line, left, patch_width, screen_width)
          )
        else
          acc
        end
      end)
    end
  end

  def patch_lines(lines, _fragment, _viewport, _screen_width), do: lines

  def patch_output(output, fragment, %{top: top, height: height} = viewport, screen_width)
      when is_binary(output) and is_binary(fragment) and is_integer(top) and top >= 0 and
             is_integer(height) and height > 0 do
    lines = :binary.split(output, "\n", [:global])
    required_lines = top + height
    lines = lines ++ List.duplicate("", max(required_lines - length(lines), 0))

    lines
    |> patch_lines(fragment, viewport, screen_width)
    |> Enum.join("\n")
  end

  def patch_output(output, _fragment, _viewport, _screen_width), do: output

  def fit_lines(lines, width) when is_list(lines) and is_integer(width) do
    Enum.map(lines, &fit_line(&1, width))
  end

  def fit_line(_line, width) when width <= 0, do: ""

  def fit_line(line, width) when is_binary(line) and is_integer(width) do
    if BackBreeze.Utils.string_length(line) > width do
      {layer_map, _max_x, _max_y} = LayerMap.generate(line, %{}, 0, 0)

      layer_map
      |> LayerMap.filter(%{start_x: 0, start_y: 0, max_x: width - 1, max_y: 0})
      |> LayerMap.to_content(width, 1)
    else
      line
    end
  end

  def fit_line(_line, _width), do: ""

  def child_patch_payload(fragment, viewport) do
    fragment
    |> child_patch_lines(viewport.height)
    |> Enum.with_index()
    |> Enum.map(fn {line, row_offset} ->
      row = Integer.to_string(viewport.top + row_offset + 1)
      col = Integer.to_string(viewport.left + 1)

      [
        "\e[",
        row,
        ";",
        col,
        "H",
        line
      ]
    end)
    |> IO.iodata_to_binary()
  end

  defp full_redraw_payload(lines, overlays, screen_width) do
    output =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, row} ->
        write_row_payload(row, line, screen_width)
      end)
      |> IO.iodata_to_binary()

    overlay_output = Breeze.TerminalOverlay.render_overlays(overlays)
    IO.iodata_to_binary(["\e[2J\e[H", output, overlay_output])
  end

  defp patch_line(line, fragment, left, width, screen_width) do
    {line_map, _max_x, _max_y} = LayerMap.generate(line || "", %{}, 0, 0)
    patch_map = patch_layer_map(fragment, width)
    line_map = LayerMap.clear_covered_by_source(line_map, patch_map, {left, 0})
    {line_map, _max_x, _max_y} = LayerMap.merge(line_map, patch_map, {left, 0})
    LayerMap.to_content(line_map, screen_width, 1)
  end

  defp patch_layer_map(fragment, width) do
    {blank_map, _max_x, _max_y} =
      LayerMap.generate(String.duplicate(" ", width), %{}, 0, 0)

    {fragment_map, _max_x, _max_y} = LayerMap.generate(fragment, %{}, 0, 0)

    fragment_map =
      LayerMap.filter(fragment_map, %{
        start_x: 0,
        start_y: 0,
        max_x: width - 1,
        max_y: 0
      })

    {patch_map, _max_x, _max_y} = LayerMap.merge(blank_map, fragment_map, {0, 0})
    patch_map
  end

  defp changed_base_rows(prev_lines, lines) do
    do_changed_base_rows(prev_lines, lines, 0, MapSet.new())
  end

  defp do_changed_base_rows(_prev_lines, [], _row, changed_rows), do: changed_rows

  defp do_changed_base_rows([line | prev_lines], [line | lines], row, changed_rows) do
    do_changed_base_rows(prev_lines, lines, row + 1, changed_rows)
  end

  defp do_changed_base_rows([_prev_line | prev_lines], [_line | lines], row, changed_rows) do
    do_changed_base_rows(prev_lines, lines, row + 1, MapSet.put(changed_rows, row))
  end

  defp do_changed_base_rows([], ["" | lines], row, changed_rows) do
    do_changed_base_rows([], lines, row + 1, changed_rows)
  end

  defp do_changed_base_rows([], [_line | lines], row, changed_rows) do
    do_changed_base_rows([], lines, row + 1, MapSet.put(changed_rows, row))
  end

  defp changed_overlay_rows(prev_overlays, overlays) do
    prev_map = overlay_row_map(prev_overlays)
    next_map = overlay_row_map(overlays)

    Map.keys(prev_map)
    |> Kernel.++(Map.keys(next_map))
    |> MapSet.new()
    |> Enum.reduce(MapSet.new(), fn row, acc ->
      if Map.get(prev_map, row, MapSet.new()) == Map.get(next_map, row, MapSet.new()) do
        acc
      else
        MapSet.put(acc, row)
      end
    end)
  end

  defp overlay_row_map(overlays) do
    Enum.reduce(overlays, %{}, fn overlay, acc ->
      sig = overlay_signature(overlay)

      Enum.reduce(overlay_rows(overlay), acc, fn row, row_acc ->
        Map.update(row_acc, row, MapSet.new([sig]), &MapSet.put(&1, sig))
      end)
    end)
  end

  defp overlay_signature(overlay) do
    {Map.get(overlay, :x), Map.get(overlay, :y), Breeze.TerminalOverlay.render_overlay(overlay)}
  end

  defp patch_only_overlay_rows(prev_overlays, overlays, changed_overlay_rows) do
    prev_map = overlay_row_map_by_row(prev_overlays)
    next_map = overlay_row_map_by_row(overlays)

    Enum.reduce(changed_overlay_rows, MapSet.new(), fn row, acc ->
      prev_row_overlays = Map.get(prev_map, row, [])
      next_row_overlays = Map.get(next_map, row, [])

      if patch_only_overlay_row?(prev_row_overlays, next_row_overlays) do
        MapSet.put(acc, row)
      else
        acc
      end
    end)
  end

  defp patch_only_overlay_row?(prev_overlays, next_overlays)
       when prev_overlays != [] and next_overlays != [] do
    Enum.all?(prev_overlays ++ next_overlays, &Map.get(&1, :patch_only, false))
  end

  defp patch_only_overlay_row?(_prev_overlays, _next_overlays), do: false

  defp overlay_row_map_by_row(overlays) do
    Enum.reduce(overlays, %{}, fn overlay, acc ->
      Enum.reduce(overlay_rows(overlay), acc, fn row, row_acc ->
        Map.update(row_acc, row, [overlay], &[overlay | &1])
      end)
    end)
  end

  defp row_patch_payload(lines, changed_rows, screen_width) do
    lines = List.to_tuple(lines)
    line_count = tuple_size(lines)

    changed_rows
    |> Enum.sort()
    |> Enum.map(fn row ->
      line = line_at(lines, row, line_count)
      write_row_payload(row, line, screen_width)
    end)
    |> IO.iodata_to_binary()
  end

  defp line_at(lines, row, line_count) when row < 0 do
    tuple_line_at(lines, line_count + row, line_count)
  end

  defp line_at(lines, row, line_count), do: tuple_line_at(lines, row, line_count)

  defp tuple_line_at(lines, row, line_count) when row >= 0 and row < line_count,
    do: elem(lines, row)

  defp tuple_line_at(_lines, _row, _line_count), do: ""

  defp write_row_payload(row, line, screen_width) do
    visible_width = visible_width(line)
    row_position = ["\e[", Integer.to_string(row + 1), ";1H"]
    line_payload = row_line_payload(line, row_position)

    if visible_width >= screen_width do
      [
        row_position,
        line_payload
      ]
    else
      [
        row_position,
        line_payload,
        "\e[",
        Integer.to_string(row + 1),
        ";",
        Integer.to_string(visible_width + 1),
        "H\e[K"
      ]
    end
  end

  defp visible_width(line) when is_binary(line) do
    BackBreeze.Utils.string_length(line)
  end

  defp row_line_payload(line, row_position) do
    if wide_glyph_line?(line) do
      [wide_background_line(line), row_position, line]
    else
      line
    end
  end

  defp wide_glyph_line?(line) do
    line
    |> BackBreeze.Utils.strip_escape_chars()
    |> String.graphemes()
    |> Enum.any?(&(BackBreeze.Ucwidth.width(&1) > 1))
  end

  defp wide_background_line(line), do: do_wide_background_line(line, [])

  defp do_wide_background_line("", acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp do_wide_background_line(<<"\e[", rest::binary>>, acc) do
    case :binary.match(rest, "m") do
      {index, 1} ->
        <<params::binary-size(^index), "m", rest::binary>> = rest
        do_wide_background_line(rest, [["\e[", params, "m"] | acc])

      :nomatch ->
        do_wide_background_text(<<"\e[", rest::binary>>, acc)
    end
  end

  defp do_wide_background_line(line, acc), do: do_wide_background_text(line, acc)

  defp do_wide_background_text(<<codepoint::utf8, rest::binary>>, acc) do
    width = codepoint |> BackBreeze.Ucwidth.width_codepoint() |> max(0)
    do_wide_background_line(rest, [String.duplicate(" ", width) | acc])
  end

  defp overlay_patch_payload(overlays, changed_rows) do
    overlays
    |> Enum.filter(&overlay_intersects_rows?(&1, changed_rows))
    |> Breeze.TerminalOverlay.render_overlays()
  end

  defp overlay_intersects_rows?(overlay, rows) do
    Enum.any?(overlay_rows(overlay), &MapSet.member?(rows, &1))
  end

  defp overlay_rows(overlay) do
    y = Map.get(overlay, :y, 0)
    height = Map.get(overlay, :height, 1)

    height =
      if is_integer(height) and height > 0 do
        height
      else
        1
      end

    y..(y + height - 1)
  end

  # Child patches must repaint the full live viewport height so stale rows from a
  # larger prior child frame do not bleed through after the child shrinks.
  defp child_patch_lines(fragment, height) when is_integer(height) and height > 0 do
    lines =
      fragment
      |> :binary.split("\n", [:global])
      |> Enum.take(height)

    lines ++ List.duplicate("", max(height - length(lines), 0))
  end

  defp child_patch_lines(fragment, _height), do: :binary.split(fragment, "\n", [:global])
end
