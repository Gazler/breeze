defmodule Breeze.Charts.Line do
  @moduledoc false

  import Bitwise
  alias BackBreeze.TextSpan
  import BackBreeze.Utils, only: [string_length: 1]

  def render(data, series, width, height, bounds) do
    unless is_integer(width) and width > 0 and is_integer(height) and height > 0 do
      raise ArgumentError, "line chart width and height must be positive integers"
    end

    {xs, series} = Breeze.Charts.Data.prepare(data, series)
    categorical? = is_binary(List.first(xs))

    if categorical? and (bounds[:x_min] != nil or bounds[:x_max] != nil) do
      raise ArgumentError, "line chart x bounds require numeric x values"
    end

    unless categorical? or xs == Enum.sort(xs) do
      raise ArgumentError, "line chart data must have nondecreasing x values"
    end

    coordinates = if categorical?, do: Enum.with_index(xs, fn _, index -> index end), else: xs
    series = Enum.map(series, &Map.put(&1, :points, Enum.zip(coordinates, &1.values)))
    points = Enum.flat_map(series, & &1.points)
    {xmin, xmax} = domain(Enum.map(points, &elem(&1, 0)), bounds[:x_min], bounds[:x_max])
    {ymin, ymax} = domain(Enum.map(points, &elem(&1, 1)), bounds[:min], bounds[:max])

    labels = if points == [], do: ["", ""], else: [label(ymax), label(ymin)]
    margin = min(Enum.max(Enum.map(labels, &string_length/1)) + 1, max(width - 2, 0))
    plot_width = width - margin - 1
    plot_height = height - 3

    if plot_width > 0 and plot_height > 0 do
      domain = {xmin, xmax, ymin, ymax}
      grid = draw(series, domain, plot_width * 2, plot_height * 4)

      rows =
        for row <- 0..(plot_height - 1) do
          tick =
            cond do
              row == 0 -> List.first(labels)
              row == plot_height - 1 -> List.last(labels)
              true -> ""
            end

          [
            TextSpan.new(pad(tick, margin) <> "│")
            | for column <- 0..(plot_width - 1) do
                case Map.get(grid, {column, row}) do
                  nil ->
                    TextSpan.new(" ")

                  {mask, color} ->
                    TextSpan.new(<<0x2800 + mask::utf8>>, %{foreground_color: color})
                end
              end
          ]
        end

      axis = [
        TextSpan.new(String.duplicate(" ", margin) <> "└" <> String.duplicate("─", plot_width))
      ]

      ticks =
        cond do
          points == [] ->
            ""

          categorical? and length(xs) == 1 ->
            text = Breeze.Charts.Text.truncate(hd(xs), plot_width)
            String.duplicate(" ", div(plot_width - string_length(text), 2)) <> text

          categorical? ->
            end_labels(hd(xs), List.last(xs), plot_width)

          true ->
            end_labels(label(xmin), label(xmax), plot_width)
        end

      xlabels = [TextSpan.new(String.duplicate(" ", margin + 1) <> ticks)]
      join_rows(rows ++ [axis, xlabels, legend(series, width)])
    else
      join_rows(List.duplicate([TextSpan.new(String.duplicate(" ", width))], height))
    end
  end

  defp domain(values, low, high) do
    unless (is_nil(low) or is_number(low)) and (is_nil(high) or is_number(high)) do
      raise ArgumentError, "line chart bounds must be numeric"
    end

    if low != nil and high != nil and low >= high do
      raise ArgumentError, "line chart minimum must be below maximum"
    end

    a = low || Enum.min(values, fn -> 0 end)
    b = high || Enum.max(values, fn -> 1 end)
    padding = max(max(abs(a), abs(b)) * 0.05, 1)

    cond do
      a < b -> {a, b}
      low != nil -> {a, a + padding}
      high != nil -> {b - padding, b}
      true -> {a - padding, b + padding}
    end
  end

  defp draw(series, {xmin, xmax, ymin, ymax}, width, height) do
    domain = {0, xmax - xmin, 0, ymax - ymin}

    Enum.reduce(series, %{}, fn %{points: points, color: color}, grid ->
      points = Enum.map(points, fn {x, y} -> {x - xmin, y - ymin} end)

      grid =
        Enum.reduce(points, grid, fn point, acc ->
          case clip(point, point, domain) do
            nil -> acc
            {point, _} -> put_dot(acc, project(point, domain, width, height), color)
          end
        end)

      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(grid, fn [a, b], acc ->
        case clip(a, b, domain) do
          nil ->
            acc

          {a, b} ->
            raster(
              acc,
              project(a, domain, width, height),
              project(b, domain, width, height),
              color
            )
        end
      end)
    end)
  end

  # Liang-Barsky clips in data space, including segments with both ends outside.
  defp clip({x, y}, {x2, y2}, {xmin, xmax, ymin, ymax}) do
    dx = x2 - x
    dy = y2 - y

    [{-dx, x - xmin}, {dx, xmax - x}, {-dy, y - ymin}, {dy, ymax - y}]
    |> Enum.reduce_while({0, 1}, fn
      {p, q}, range when p == 0 ->
        if q < 0, do: {:halt, nil}, else: {:cont, range}

      {p, q}, {enter, leave} ->
        t = q / p
        {enter, leave} = if p < 0, do: {max(enter, t), leave}, else: {enter, min(leave, t)}
        if enter > leave, do: {:halt, nil}, else: {:cont, {enter, leave}}
    end)
    |> case do
      nil -> nil
      {enter, leave} -> {{x + enter * dx, y + enter * dy}, {x + leave * dx, y + leave * dy}}
    end
  end

  defp project({x, y}, {xmin, xmax, ymin, ymax}, width, height) do
    {round((x - xmin) / (xmax - xmin) * (width - 1)) |> max(0) |> min(width - 1),
     round((ymax - y) / (ymax - ymin) * (height - 1)) |> max(0) |> min(height - 1)}
  end

  defp raster(grid, {x, y}, {x2, y2}, color) do
    dx = abs(x2 - x)
    dy = -abs(y2 - y)
    sx = if x < x2, do: 1, else: -1
    sy = if y < y2, do: 1, else: -1
    raster(grid, {x, y}, {x2, y2}, {dx, dy, sx, sy}, dx + dy, color)
  end

  defp raster(grid, {x, y} = point, target, {dx, dy, sx, sy} = steps, error, color) do
    grid = put_dot(grid, point, color)

    if point == target do
      grid
    else
      twice = 2 * error
      {x, error} = if twice >= dy, do: {x + sx, error + dy}, else: {x, error}
      {y, error} = if twice <= dx, do: {y + sy, error + dx}, else: {y, error}
      raster(grid, {x, y}, target, steps, error, color)
    end
  end

  defp put_dot(grid, {x, y}, color) do
    bit = elem({0, 1, 2, 6, 3, 4, 5, 7}, rem(x, 2) * 4 + rem(y, 4))
    key = {div(x, 2), div(y, 4)}
    {mask, _} = Map.get(grid, key, {0, nil})
    Map.put(grid, key, {bor(mask, 1 <<< bit), color})
  end

  defp legend(series, width) do
    {spans, _} =
      Enum.map_reduce(series, width, fn %{name: name, color: color}, remaining ->
        text = Breeze.Charts.Text.truncate("● " <> name <> "  ", remaining)
        {TextSpan.new(text, %{foreground_color: color}), remaining - string_length(text)}
      end)

    spans
  end

  defp label(value) when is_integer(value), do: Integer.to_string(value)
  defp label(value), do: Float.to_string(value)

  defp pad(text, width) do
    text = if string_length(text) <= width, do: text, else: ""
    String.duplicate(" ", max(width - string_length(text), 0)) <> text
  end

  defp end_labels(left, right, width) do
    if string_length(left) + string_length(right) < width do
      left <> String.duplicate(" ", width - string_length(left) - string_length(right)) <> right
    else
      if string_length(left) <= width, do: left, else: ""
    end
  end

  defp join_rows(rows), do: rows |> Enum.intersperse([TextSpan.new("\n")]) |> List.flatten()
end
