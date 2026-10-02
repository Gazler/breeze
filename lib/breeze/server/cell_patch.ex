defmodule Breeze.Server.CellPatch do
  @moduledoc false

  # Target RGB recoloring (including modal dimming), leaving ordinary updates
  # on the cheaper row path. Only self-contained SGR rows with single-column
  # glyphs are eligible.
  # Unknown controls and wide glyphs retain Frame's existing repaint path.
  def new_cache,
    do: %{
      styles: %{},
      transitions: %{},
      text: %{},
      parts: %{},
      patterns: %{
        sgr_end: :binary.compile_pattern("m"),
        reset: :binary.compile_pattern("\e[0m"),
        escape: :binary.compile_pattern("\e"),
        rgb: :binary.compile_pattern(["38;2;", "48;2;"])
      }
    }

  def build(previous, current, row, width) do
    {patch, _cache} = build(previous, current, row, width, new_cache())
    patch
  end

  # The caller shares this cache across rows, then discards it after the frame.
  def build(previous, current, row, width, nil) do
    # Plain rows need no parser state or compiled search patterns.
    if :binary.match(previous, "\e") == :nomatch do
      {nil, nil}
    else
      build(previous, current, row, width, new_cache())
    end
  end

  def build(previous, current, row, width, cache) do
    if :binary.match(previous, cache.patterns.rgb) != :nomatch and
         :binary.match(current, cache.patterns.rgb) != :nomatch do
      case recolor(previous, current, row, width, cache) do
        {:ok, patch, cache} -> {patch, cache}
        {:redraw, cache} -> {nil, cache}
        :fallback -> build_cells(previous, current, row, width, cache)
      end
    else
      {nil, cache}
    end
  end

  defp build_cells(previous, current, row, width, cache) do
    with {:ok, old, cache} <- cells(previous, width, cache),
         {:ok, new, cache} <- cells(current, width, cache) do
      {output, cache} = diff(old, new, 0, row, false, :unknown, cache, [])

      patch = if output == [], do: "", else: IO.iodata_to_binary([Enum.reverse(output), "\e[0m"])
      {patch, cache}
    else
      _ -> {nil, cache}
    end
  end

  # Most backdrop rows only change color. Retain whole text spans on this
  # path; different text, non-self-contained spans and controls use cell diffs.
  defp recolor(previous, current, row, width, cache) do
    with {:ok, old, cache} <- spans(previous, cache),
         {:ok, new, cache} <- spans(current, cache),
         {:ok, output, cache} <-
           recolor_spans(old, new, row, width, 0, false, :unknown, cache, []) do
      payload =
        if output == [], do: "", else: IO.iodata_to_binary([Enum.reverse(output), "\e[0m"])

      {:ok, payload, cache}
    else
      {:redraw, cache} -> {:redraw, cache}
      _ -> :fallback
    end
  end

  defp spans(line, cache),
    do: span_segments(:binary.split(line, cache.patterns.reset, [:global]), [], cache)

  defp span_segments([""], acc, cache), do: {:ok, Enum.reverse(acc), cache}

  defp span_segments(["\e[" <> segment = full | rest], acc, cache) do
    case :binary.split(segment, cache.patterns.sgr_end) do
      [code, text] when code != "" ->
        style = binary_part(full, 0, byte_size(code) + 3)

        case cache.styles do
          %{^style => data} ->
            span_segments(rest, [{style, data.blank, text} | acc], cache)

          _ ->
            if sgr_params?(code) do
              {data, cache} = style_data(style, cache)
              span_segments(rest, [{style, data.blank, text} | acc], cache)
            else
              :unsupported
            end
        end

      _ ->
        :unsupported
    end
  end

  defp span_segments(_, _, _), do: :unsupported

  # A single color-only span whose background changes must repaint every
  # cell. Its original row encoding is already cheaper than a cell patch.
  defp recolor_spans(
         [{old_style, _, text}],
         [{new_style, _, text}],
         row,
         width,
         0,
         false,
         :unknown,
         cache,
         []
       ) do
    {old, cache} = style_data(old_style, cache)
    {new, cache} = style_data(new_style, cache)

    case {old.colors, new.colors} do
      {{:ok, before}, {:ok, after_colors}} when before.background != after_colors.background ->
        {:redraw, cache}

      _ ->
        recolor_parts(
          [{old_style, old.blank, text}],
          [{new_style, new.blank, text}],
          row,
          width,
          0,
          false,
          :unknown,
          cache,
          []
        )
    end
  end

  defp recolor_spans(old, new, row, width, x, writing, style, cache, output),
    do: recolor_parts(old, new, row, width, x, writing, style, cache, output)

  defp recolor_parts([], [], _row, _width, _x, _writing, _style, cache, output),
    do: {:ok, output, cache}

  defp recolor_parts(
         [{old_style, old_blank, text} | old],
         [{new_style, new_blank, text} | new],
         row,
         width,
         x,
         writing,
         style,
         cache,
         output
       ) do
    with {:ok, parts, size, cache} <- text_parts(text, cache),
         true <- x + size <= width do
      {x, writing, style, cache, output} =
        Enum.reduce(parts, {x, writing, style, cache, output}, fn {text, size, blank?},
                                                                  {x, writing, style, cache,
                                                                   output} ->
          old_cell_style = if blank?, do: old_blank, else: old_style
          new_cell_style = if blank?, do: new_blank, else: new_style

          if old_cell_style == new_cell_style do
            {x + size, false, style, cache, output}
          else
            position =
              if writing,
                do: [],
                else: ["\e[", Integer.to_string(row + 1), ";", Integer.to_string(x + 1), "H"]

            {change, cache} = style_change(style, new_cell_style, cache)
            {x + size, true, new_cell_style, cache, [[position, change, text] | output]}
          end
        end)

      recolor_spans(old, new, row, width, x, writing, style, cache, output)
    else
      _ ->
        # Unsupported glyphs/widths cannot succeed in the cell parser either.
        # Embedded SGR is different: the general parser may handle those styles.
        if :binary.match(text, cache.patterns.escape) == :nomatch,
          do: {:redraw, cache},
          else: :unsupported
    end
  end

  defp recolor_parts(_, _, _, _, _, _, _, _, _), do: :unsupported

  defp text_parts(text, cache) do
    case cache.parts do
      %{^text => {parts, width}} ->
        {:ok, parts, width, cache}

      _ ->
        case ascii_parts(text, text, 0, 0, nil, []) do
          {:ok, parts, width} ->
            {:ok, parts, width, %{cache | parts: Map.put(cache.parts, text, {parts, width})}}

          :unsupported ->
            unicode_parts(text, cache)
        end
    end
  end

  defp unicode_parts(text, cache) do
    with {:ok, runs, width, cache} <- text_runs(text, cache) do
      parts =
        runs
        |> Enum.chunk_by(fn {{char, _}, _} -> char == " " end)
        |> Enum.map(fn group ->
          blank? = match?([{{" ", _}, _} | _], group)
          text = Enum.map_join(group, fn {{char, _}, count} -> String.duplicate(char, count) end)
          size = Enum.reduce(group, 0, fn {_, count}, size -> size + count end)
          {text, size, blank?}
        end)

      {:ok, parts, width, %{cache | parts: Map.put(cache.parts, text, {parts, width})}}
    end
  end

  defp ascii_parts("", source, start, x, blank, acc) do
    acc =
      if start == x,
        do: acc,
        else: [{binary_part(source, start, x - start), x - start, blank} | acc]

    {:ok, Enum.reverse(acc), x}
  end

  defp ascii_parts(<<char, rest::binary>>, source, start, x, blank, acc) when char in 32..126 do
    next_blank = char == 32

    if blank == nil or blank == next_blank do
      ascii_parts(rest, source, start, x + 1, next_blank, acc)
    else
      part = {binary_part(source, start, x - start), x - start, blank}
      ascii_parts(rest, source, x, x + 1, next_blank, [part | acc])
    end
  end

  defp ascii_parts(_, _, _, _, _, _), do: :unsupported

  # Compare repeated-cell runs without expanding blank padding into cells or
  # allocating zipped/indexed/chunked copies of the screen.
  defp diff([], [], _x, _row, _writing?, _style, cache, output), do: {output, cache}

  defp diff(
         [{before, old_count} | old],
         [{after_cell, new_count} | new],
         x,
         row,
         writing?,
         style,
         cache,
         output
       ) do
    count = min(old_count, new_count)
    old = if old_count == count, do: old, else: [{before, old_count - count} | old]
    new = if new_count == count, do: new, else: [{after_cell, new_count - count} | new]

    if before == after_cell do
      diff(old, new, x + count, row, false, style, cache, output)
    else
      {char, current} = after_cell

      position =
        if writing?,
          do: [],
          else: ["\e[", Integer.to_string(row + 1), ";", Integer.to_string(x + 1), "H"]

      {change, cache} = style_change(style, current, cache)
      text = if count == 1, do: char, else: String.duplicate(char, count)
      diff(old, new, x + count, row, true, current, cache, [[position, change, text] | output])
    end
  end

  defp style_change(same, same, cache), do: {"", cache}
  defp style_change(:unknown, current, cache), do: {["\e[0m", current], cache}

  defp style_change(previous, current, cache) do
    key = {previous, current}

    case cache.transitions do
      %{^key => change} ->
        {change, cache}

      _ ->
        {old, cache} = style_data(previous, cache)
        {new, cache} = style_data(current, cache)
        change = color_change(old.colors, new.colors, current)
        {change, %{cache | transitions: Map.put(cache.transitions, key, change)}}
    end
  end

  defp color_change({:ok, old}, {:ok, new}, _current) do
    codes = for key <- [:background, :foreground], old[key] != new[key], do: new[key]
    if codes == [], do: "", else: ["\e[", Enum.intersperse(codes, ";"), "m"]
  end

  defp color_change(_, _, current), do: ["\e[0m", current]

  defp style_data(style, cache) do
    case cache.styles do
      %{^style => data} ->
        {data, cache}

      _ ->
        data = %{blank: blank_style(style), colors: colors(style)}
        {data, %{cache | styles: Map.put(cache.styles, style, data)}}
    end
  end

  # A cursor move leaves SGR intact. Retain known color-only state across runs;
  # attributes such as bold or reverse use a full reset to prevent style leaks.
  defp colors(style) do
    Regex.scan(~r/\e\[([0-9;]+)m/, style)
    |> Enum.flat_map(fn [_, params] -> String.split(params, ";") end)
    |> color_params(%{background: "49", foreground: "39"})
  end

  defp color_params([code, "2", r, g, b | rest], colors) when code in ["38", "48"] do
    key = if code == "38", do: :foreground, else: :background
    color_params(rest, Map.put(colors, key, Enum.join([code, "2", r, g, b], ";")))
  end

  defp color_params([code, "5", n | rest], colors) when code in ["38", "48"] do
    key = if code == "38", do: :foreground, else: :background
    color_params(rest, Map.put(colors, key, Enum.join([code, "5", n], ";")))
  end

  defp color_params([code | rest], colors) do
    case Integer.parse(code) do
      {n, ""} when n in 30..37 or n == 39 or n in 90..97 ->
        color_params(rest, Map.put(colors, :foreground, code))

      {n, ""} when n in 40..47 or n == 49 or n in 100..107 ->
        color_params(rest, Map.put(colors, :background, code))

      _ ->
        :unsupported
    end
  end

  defp color_params([], colors), do: {:ok, colors}

  defp cells(line, width, cache) do
    with {:ok, cells, remaining, cache} <- parse(line, {"", ""}, [], width, cache) do
      {:ok, if(remaining == 0, do: cells, else: cells ++ [{{" ", ""}, remaining}]), cache}
    end
  end

  defp parse("", {"", ""}, acc, remaining, cache),
    do: {:ok, Enum.reverse(acc), remaining, cache}

  defp parse("\e[0m" <> rest, _styles, acc, remaining, cache),
    do: parse(rest, {"", ""}, acc, remaining, cache)

  defp parse("\e[m" <> rest, _styles, acc, remaining, cache),
    do: parse(rest, {"", ""}, acc, remaining, cache)

  defp parse("\e[" <> rest = text, {style, _blank}, acc, remaining, cache) do
    case :binary.match(rest, cache.patterns.sgr_end) do
      {size, 1} ->
        sequence = binary_part(text, 0, size + 3)
        next = if style == "", do: sequence, else: style <> sequence
        tail = binary_part(rest, size + 1, byte_size(rest) - size - 1)

        case cache.styles do
          %{^next => data} ->
            parse(tail, {next, data.blank}, acc, remaining, cache)

          _ ->
            if sgr_params?(binary_part(rest, 0, size)) do
              {data, cache} = style_data(next, cache)
              parse(tail, {next, data.blank}, acc, remaining, cache)
            else
              :unsupported
            end
        end

      _ ->
        :unsupported
    end
  end

  defp parse(text, {style, blank} = styles, acc, remaining, cache) do
    size =
      case :binary.match(text, cache.patterns.escape) do
        :nomatch -> byte_size(text)
        {size, 1} -> size
      end

    if size == 0 do
      :unsupported
    else
      chunk = binary_part(text, 0, size)
      rest = binary_part(text, size, byte_size(text) - size)

      with {:ok, runs, width, cache} <- text_runs(chunk, cache),
           true <- width <= remaining do
        acc =
          Enum.reduce(runs, acc, fn {{char, _}, count}, acc ->
            cell = {char, if(char == " ", do: blank, else: style)}

            case acc do
              [{^cell, previous_count} | tail] -> [{cell, previous_count + count} | tail]
              _ -> [{cell, count} | acc]
            end
          end)

        parse(rest, styles, acc, remaining - width, cache)
      else
        _ -> :unsupported
      end
    end
  end

  # Text geometry is independent of color. Reuse it across the old/new rows
  # and repeated fragments within the frame (padding, borders, status labels).
  defp text_runs(text, cache) do
    case cache.text do
      %{^text => {runs, width}} ->
        {:ok, runs, width, cache}

      _ ->
        with {:ok, runs, remaining, _} <- parse_text(text, {"", ""}, [], byte_size(text), cache) do
          width = byte_size(text) - remaining
          {:ok, runs, width, %{cache | text: Map.put(cache.text, text, {runs, width})}}
        end
    end
  end

  defp parse_text("", _styles, acc, remaining, cache),
    do: {:ok, Enum.reverse(acc), remaining, cache}

  # ASCII followed by ASCII/control bytes cannot be part of a wider grapheme.
  # Keep the Unicode path for an ASCII base followed by a combining character.
  defp parse_text("  " <> rest, styles, acc, remaining, cache) do
    {count, rest} = take_spaces(rest, 2)

    if count <= remaining,
      do: append_run(" ", count, rest, styles, acc, remaining, cache),
      else: :unsupported
  end

  defp parse_text(<<char, next, _::binary>> = text, styles, acc, remaining, cache)
       when char in 32..126 and next < 128 and remaining > 0 do
    <<_, rest::binary>> = text
    append_cell(<<char>>, rest, styles, acc, remaining, cache)
  end

  defp parse_text(<<char>>, styles, acc, remaining, cache)
       when char in 32..126 and remaining > 0,
       do: append_cell(<<char>>, "", styles, acc, remaining, cache)

  # Box-drawing codepoints are one column. Avoid the general Unicode width
  # machinery when the following codepoint cannot extend this grapheme.
  defp parse_text(<<char::utf8, next::utf8, _::binary>> = text, styles, acc, remaining, cache)
       when char in 0x2500..0x257F and (next < 128 or next in 0x2500..0x257F) and remaining > 0 do
    <<glyph::binary-size(3), rest::binary>> = text
    append_cell(glyph, rest, styles, acc, remaining, cache)
  end

  defp parse_text(<<char::utf8>> = glyph, styles, acc, remaining, cache)
       when char in 0x2500..0x257F and remaining > 0,
       do: append_cell(glyph, "", styles, acc, remaining, cache)

  defp parse_text(<<char::utf8, _::binary>> = text, styles, acc, remaining, cache)
       when char >= 32 and char != 127 and remaining > 0 do
    {grapheme, rest} = String.next_grapheme(text)

    if BackBreeze.Ucwidth.width(grapheme) == 1,
      do: append_cell(grapheme, rest, styles, acc, remaining, cache),
      else: :unsupported
  end

  defp parse_text(_, _, _, _, _), do: :unsupported

  defp append_cell(char, rest, styles, acc, remaining, cache) do
    append_run(char, 1, rest, styles, acc, remaining, cache)
  end

  defp append_run(char, count, rest, {style, blank} = styles, acc, remaining, cache) do
    cell_style = if char == " ", do: blank, else: style
    cell = {char, cell_style}

    acc =
      case acc do
        [{^cell, previous_count} | tail] -> [{cell, previous_count + count} | tail]
        _ -> [{cell, count} | acc]
      end

    parse_text(rest, styles, acc, remaining - count, cache)
  end

  defp take_spaces(" " <> rest, count), do: take_spaces(rest, count + 1)

  defp take_spaces(<<next, _::binary>> = rest, count) when next >= 128,
    do: {count - 1, " " <> rest}

  defp take_spaces(rest, count), do: {count, rest}

  # Validate only uncached sequences. Searching/slicing is done by binary BIFs.
  defp sgr_params?(""), do: true

  defp sgr_params?(<<char, rest::binary>>) when char in ?0..?9 or char == ?;,
    do: sgr_params?(rest)

  defp sgr_params?(_), do: false

  # Foreground is invisible on plain spaces. Only normalize color-only styles:
  # reverse video, underline, etc. can make a space's foreground visible.
  defp blank_style(style) do
    sequences = Regex.scan(~r/\e\[([0-9;]+)m/, style)

    Enum.reduce_while(sequences, "", fn [_, params], acc ->
      case background_params(String.split(params, ";"), []) do
        {:ok, []} -> {:cont, acc}
        {:ok, params} -> {:cont, acc <> "\e[" <> Enum.join(params, ";") <> "m"}
        :unsupported -> {:halt, style}
      end
    end)
  end

  defp background_params(["38", "2", _, _, _ | rest], acc), do: background_params(rest, acc)
  defp background_params(["38", "5", _ | rest], acc), do: background_params(rest, acc)

  defp background_params(["48", "2", r, g, b | rest], acc),
    do: background_params(rest, [b, g, r, "2", "48" | acc])

  defp background_params(["48", "5", n | rest], acc),
    do: background_params(rest, [n, "5", "48" | acc])

  defp background_params([code | rest], acc) do
    case Integer.parse(code) do
      {n, ""} when n in 30..37 or n == 39 or n in 90..97 ->
        background_params(rest, acc)

      {n, ""} when n in 40..47 or n == 49 or n in 100..107 ->
        background_params(rest, [code | acc])

      _ ->
        :unsupported
    end
  end

  defp background_params([], acc), do: {:ok, Enum.reverse(acc)}
end
