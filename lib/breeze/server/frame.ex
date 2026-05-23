defmodule Breeze.Server.Frame do
  @moduledoc false

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
        overlay_patch_payload(overlays, changed_overlay_rows)
      ])
    end
  end

  def invalidate_patched_rows(nil, _viewport), do: nil

  def invalidate_patched_rows(lines, %{top: top, height: height})
      when is_list(lines) and is_integer(top) and is_integer(height) and height > 0 do
    last_row = top + height - 1

    lines
    |> Enum.with_index()
    |> Enum.map(fn
      {_line, row} when row >= top and row <= last_row -> nil
      {line, _row} -> line
    end)
  end

  def invalidate_patched_rows(lines, _viewport), do: lines

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

  defp changed_base_rows(prev_lines, lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {line, row}, acc ->
      if line == Enum.at(prev_lines, row, "") do
        acc
      else
        MapSet.put(acc, row)
      end
    end)
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
      row = Map.get(overlay, :y, 0)
      sig = overlay_signature(overlay)
      Map.update(acc, row, MapSet.new([sig]), &MapSet.put(&1, sig))
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
      Map.update(acc, Map.get(overlay, :y, 0), [overlay], &[overlay | &1])
    end)
  end

  defp row_patch_payload(lines, changed_rows, screen_width) do
    changed_rows
    |> Enum.sort()
    |> Enum.map(fn row ->
      line = Enum.at(lines, row, "")
      write_row_payload(row, line, screen_width)
    end)
    |> IO.iodata_to_binary()
  end

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
        <<params::binary-size(index), "m", rest::binary>> = rest
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
    |> Enum.filter(&MapSet.member?(changed_rows, Map.get(&1, :y, 0)))
    |> Breeze.TerminalOverlay.render_overlays()
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
