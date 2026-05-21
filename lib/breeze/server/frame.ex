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

  def build_inline_payload(
        prev_lines,
        lines,
        prev_overlays,
        overlays,
        screen_width,
        reserved_height
      ) do
    reserved_height = max(reserved_height || 0, 0)
    next_height = max(length(lines), 1)
    paint_height = max(reserved_height, next_height)

    cond do
      prev_lines == lines and prev_overlays == overlays and reserved_height >= next_height ->
        ""

      reserved_height == 0 ->
        IO.iodata_to_binary([
          reserve_inline_rows(paint_height),
          inline_rewrite_payload(lines, overlays, screen_width, paint_height, restore?: false)
        ])

      next_height > reserved_height ->
        IO.iodata_to_binary([
          restore_cursor(),
          extend_inline_rows(next_height - reserved_height),
          inline_rewrite_payload(lines, overlays, screen_width, next_height, restore?: false)
        ])

      true ->
        inline_rewrite_payload(lines, overlays, screen_width, paint_height, restore?: true)
    end
  end

  def build_inline_scrollback_payload(
        scrollback,
        lines,
        overlays,
        screen_width,
        reserved_height
      )
      when is_binary(scrollback) do
    reserved_height = max(reserved_height || 0, 0)
    next_height = max(length(lines), 1)

    IO.iodata_to_binary([
      move_to_inline_scrollback_start(reserved_height),
      normalize_scrollback(scrollback),
      inline_write_payload(lines, overlays, screen_width, next_height)
    ])
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

  defp inline_rewrite_payload(lines, overlays, screen_width, reserved_height, opts) do
    rows = lines ++ List.duplicate("", max(reserved_height - length(lines), 0))

    [
      if(Keyword.get(opts, :restore?, false), do: restore_cursor(), else: ""),
      inline_move_to_top(reserved_height),
      inline_rows_payload(rows, screen_width),
      inline_overlay_payload(overlays, reserved_height),
      save_cursor()
    ]
    |> IO.iodata_to_binary()
  end

  defp inline_write_payload(lines, overlays, screen_width, reserved_height) do
    rows = lines ++ List.duplicate("", max(reserved_height - length(lines), 0))

    [
      inline_rows_payload(rows, screen_width),
      inline_overlay_payload(overlays, reserved_height),
      save_cursor()
    ]
    |> IO.iodata_to_binary()
  end

  defp reserve_inline_rows(count) when count > 1, do: String.duplicate("\r\n", count - 1)
  defp reserve_inline_rows(_count), do: ""

  defp extend_inline_rows(count) when count > 0, do: String.duplicate("\r\n", count)
  defp extend_inline_rows(_count), do: ""

  defp inline_move_to_top(count) when count > 1, do: "\e[#{count - 1}F"
  defp inline_move_to_top(_count), do: "\r"

  defp move_to_inline_scrollback_start(reserved_height) when reserved_height > 0 do
    [restore_cursor(), inline_move_to_top(reserved_height)]
  end

  defp move_to_inline_scrollback_start(_reserved_height), do: ""

  defp normalize_scrollback(""), do: ""

  defp normalize_scrollback(scrollback) do
    scrollback =
      scrollback
      |> String.replace("\r\n", "\n")
      |> trim_scrollback_padding()
      |> String.replace("\n", "\r\n")

    if String.ends_with?(scrollback, "\r\n"), do: scrollback, else: scrollback <> "\r\n"
  end

  defp trim_scrollback_padding(scrollback) do
    scrollback
    |> String.split("\n", trim: false)
    |> Enum.map(&String.trim_trailing(&1, " "))
    |> Enum.reject(fn line -> strip_ansi(line) == "" end)
    |> Enum.join("\n")
  end

  defp strip_ansi(line) do
    String.replace(line, ~r/\e\[[0-9;?]*[ -\/]*[@-~]/, "")
  end

  defp inline_rows_payload(lines, screen_width) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      inline_row_payload(line, screen_width, index == length(lines) - 1)
    end)
    |> IO.iodata_to_binary()
  end

  defp inline_row_payload(line, screen_width, last?) do
    line =
      if visible_width(line) > screen_width do
        truncate_visible(line, screen_width)
      else
        line
      end

    next_row = if last?, do: "\e[K\r", else: "\e[K\r\n"
    ["\e[?7l", line, "\e[?7h", next_row]
  end

  defp inline_overlay_payload(overlays, reserved_height) do
    overlays
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(Map.get(&1, :visible?) == false))
    |> Enum.reject(fn overlay -> Map.get(overlay, :y, 0) >= reserved_height end)
    |> Enum.map(&inline_overlay(&1, reserved_height))
    |> IO.iodata_to_binary()
  end

  defp inline_overlay(%{x: x, y: y, content: content} = overlay, reserved_height)
       when is_binary(content) do
    [
      inline_move_to_row(x, y, reserved_height),
      if(Map.get(overlay, :no_wrap, false), do: "\e[?7l", else: ""),
      if(Map.get(overlay, :clear_line, false), do: "\e[2K", else: ""),
      content,
      if(Map.get(overlay, :no_wrap, false), do: "\e[?7h", else: ""),
      inline_move_to_bottom(y, reserved_height)
    ]
  end

  defp inline_overlay(%{x: x, y: y, char: char} = overlay, reserved_height) do
    [
      inline_move_to_row(x, y, reserved_height),
      cursor_open_code(overlay),
      char,
      Termite.Style.reset_code(),
      inline_move_to_bottom(y, reserved_height)
    ]
  end

  defp inline_overlay(_overlay, _reserved_height), do: ""

  defp inline_move_to_row(x, y, reserved_height) do
    up = max(reserved_height - y - 1, 0)
    right = max(x, 0)
    ["\e[#{up}F", if(right > 0, do: "\e[#{right}C", else: "")]
  end

  defp inline_move_to_bottom(y, reserved_height) do
    down = max(reserved_height - y - 1, 0)
    ["\r", if(down > 0, do: "\e[#{down}E", else: "")]
  end

  defp save_cursor, do: "\e7"
  defp restore_cursor, do: "\e8"

  defp cursor_open_code(overlay) do
    style =
      Termite.Style.ansi256()
      |> maybe_put_foreground(Map.get(overlay, :foreground_color, 0))
      |> maybe_put_background(Map.get(overlay, :background_color, 11))

    Termite.Style.open_code(style)
  end

  defp maybe_put_foreground(style, nil), do: style
  defp maybe_put_foreground(style, color), do: Termite.Style.foreground(style, color)

  defp maybe_put_background(style, nil), do: style
  defp maybe_put_background(style, color), do: Termite.Style.background(style, color)

  defp changed_base_rows(prev_lines, lines) do
    lines
    |> Enum.zip(prev_lines)
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn
      {{line, line}, _row}, acc -> acc
      {_pair, row}, acc -> MapSet.put(acc, row)
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

    if visible_width >= screen_width do
      [
        "\e[",
        Integer.to_string(row + 1),
        ";1H",
        line
      ]
    else
      [
        "\e[",
        Integer.to_string(row + 1),
        ";1H",
        line,
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

  defp truncate_visible(_line, width) when width <= 0 do
    ""
  end

  defp truncate_visible(line, width) do
    line
    |> String.graphemes()
    |> Enum.reduce_while({"", 0}, fn grapheme, {acc, used} ->
      next = BackBreeze.Utils.string_length(grapheme)

      if used + next > width do
        {:halt, {acc, used}}
      else
        {:cont, {acc <> grapheme, used + next}}
      end
    end)
    |> elem(0)
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
