defmodule Breeze.Server.ScrollFrame do
  @moduledoc false

  def regions(acc) do
    opted_in =
      Enum.filter(acc.elements, fn {_, flags} -> Keyword.get(flags, :"br-update") == "scroll" end)

    if opted_in == [], do: [], else: regions(acc, opted_in)
  end

  defp regions(acc, opted_in) do
    elements = Enum.sort(acc.elements)

    dimensions =
      Breeze.RenderState.build_dimensions(acc) |> Map.merge(Map.get(acc, :live_dimensions, %{}))

    regular = Enum.reject(elements, fn {_, flags} -> Keyword.get(flags, :__live_dimension__) end)

    anonymous_dimensions =
      regular |> Enum.zip(acc.dimensions) |> Map.new(fn {{idx, _}, dims} -> {idx, dims} end)

    for {idx, flags} <- Enum.sort(opted_in),
        dims = Map.get(dimensions, Keyword.get(flags, :id)) || Map.get(anonymous_dimensions, idx),
        is_map(dims) do
      Map.take(dims, [:left, :top, :width, :height])
    end
  end

  # Only full-width scrolls are emitted. The opt-in container bounds detection;
  # repairs restore every changed cell in the composed screen outside it too.
  def build(previous, current, previous_overlays, overlays, width, regions, baseline) do
    fallback = %{payload: baseline, mode: :default, baseline_bytes: byte_size(baseline)}

    with true <- regions != [] and baseline != "" and is_list(previous),
         true <- length(previous) == length(current),
         true <- Enum.all?(previous_overlays ++ overlays, &cursor_overlay?/1),
         {:ok, old} <- cells(previous, width),
         {:ok, new} <- cells(current, width) do
      old_with_cursors = dirty_overlay_rows(old, previous_overlays)

      regions
      |> Enum.filter(&valid_region?(&1, width, length(current)))
      |> Enum.flat_map(&candidates(old, new, &1))
      |> Enum.uniq()
      |> Enum.reduce(fallback, fn {top, bottom, delta}, best ->
        shifted =
          old_with_cursors |> scroll(top, bottom, delta, width) |> dirty_overlay_rows(overlays)

        payload =
          IO.iodata_to_binary([
            "\e[0m\e[#{top + 1};#{bottom + 1}r\e[#{top + 1};1H",
            "\e[#{abs(delta)}#{if delta > 0, do: "S", else: "T"}\e[r",
            repairs(shifted, new),
            "\e[0m",
            Breeze.TerminalOverlay.render_overlays(overlays)
          ])

        if byte_size(payload) < byte_size(best.payload),
          do: %{best | payload: payload, mode: :scroll},
          else: best
      end)
    else
      _ -> fallback
    end
  end

  defp valid_region?(%{left: x, top: y, width: w, height: h}, width, height) do
    is_integer(x) and is_integer(y) and is_integer(w) and is_integer(h) and
      x >= 0 and y >= 0 and w > 0 and h > 2 and x + w <= width and y + h <= height
  end

  defp valid_region?(_, _, _), do: false

  defp cursor_overlay?(%{visible?: false}), do: true

  defp cursor_overlay?(%{x: x, y: y, char: char}) do
    is_integer(x) and is_integer(y) and is_binary(char) and BackBreeze.Ucwidth.width(char) == 1
  end

  defp cursor_overlay?(_), do: false

  defp dirty_overlay_rows(rows, overlays) do
    Enum.reduce(overlays, rows, fn
      %{visible?: false}, acc ->
        acc

      %{y: y}, acc when y >= 0 and y < length(rows) ->
        List.update_at(acc, y, &Enum.map(&1, fn _ -> :unknown end))

      _, acc ->
        acc
    end)
  end

  # Find a matching run inside the container, leaving fixed headers/borders out.
  # A run must contain actual movement, not just identical blank rows.
  defp candidates(old, new, %{left: left, top: top, width: width, height: height}) do
    old_region =
      old |> Enum.slice(top, height) |> Enum.map(&Enum.slice(&1, left, width)) |> List.to_tuple()

    new_region =
      new |> Enum.slice(top, height) |> Enum.map(&Enum.slice(&1, left, width)) |> List.to_tuple()

    for delta <- Enum.flat_map(1..min(3, height - 2), &[&1, -&1]),
        run <-
          Enum.chunk_by(0..(height - 1), fn y ->
            source = y + delta
            source >= 0 and source < height and elem(new_region, y) == elem(old_region, source)
          end),
        length(run) >= 2,
        first = hd(run),
        last = List.last(run),
        first + delta >= 0 and last + delta < height,
        elem(new_region, first) == elem(old_region, first + delta),
        Enum.any?(run, &(elem(new_region, &1) != elem(old_region, &1))) do
      {top + min(first, first + delta), top + max(last, last + delta), delta}
    end
  end

  defp scroll(rows, top, bottom, delta, width) do
    indexed = List.to_tuple(rows)
    blank = List.duplicate({" ", ""}, width)

    Enum.with_index(rows, fn row, y ->
      cond do
        y < top or y > bottom -> row
        y + delta < top or y + delta > bottom -> blank
        true -> elem(indexed, y + delta)
      end
    end)
  end

  defp cells(lines, width) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, rows} ->
      case parse(line, "", []) do
        {:ok, row} when length(row) <= width ->
          {:cont, {:ok, [row ++ List.duplicate({" ", ""}, width - length(row)) | rows]}}

        _ ->
          {:halt, :unsupported}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp parse("", "", acc), do: {:ok, Enum.reverse(acc)}

  defp parse("\e[" <> rest, style, acc) do
    case Regex.run(~r/^([0-9;]*)m(.*)$/s, rest) do
      [_, code, tail] ->
        next = if code in ["", "0"], do: "", else: style <> "\e[" <> code <> "m"
        parse(tail, next, acc)

      _ ->
        :unsupported
    end
  end

  defp parse(<<c, rest::binary>>, style, acc) when c in 32..126,
    do: parse(rest, style, [{<<c>>, style} | acc])

  defp parse(<<c::utf8, _::binary>> = text, style, acc) when c > 127 do
    {grapheme, rest} = String.next_grapheme(text)

    if BackBreeze.Ucwidth.width(grapheme) == 1 do
      parse(rest, style, [{grapheme, style} | acc])
    else
      :unsupported
    end
  end

  defp parse(_, _, _), do: :unsupported

  defp repairs(old, new) do
    Enum.zip(old, new)
    |> Enum.with_index(fn {before, after_row}, y ->
      Enum.zip(before, after_row)
      |> Enum.with_index()
      |> Enum.chunk_by(fn {{a, b}, _x} -> a == b end)
      |> Enum.map(fn chunk ->
        case hd(chunk) do
          {{same, same}, _} ->
            ""

          {_, x} ->
            ["\e[#{y + 1};#{x + 1}H", encode(Enum.map(chunk, fn {{_, cell}, _} -> cell end))]
        end
      end)
    end)
  end

  defp encode(cells) do
    cells
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn group -> ["\e[0m", elem(hd(group), 1), Enum.map(group, &elem(&1, 0))] end)
  end
end
