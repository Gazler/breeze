defmodule Breeze.Charts.Bar do
  @moduledoc false

  alias BackBreeze.TextSpan
  alias Breeze.Charts.Text

  import BackBreeze.Utils, only: [string_length: 1]

  @fractions {"", "▏", "▎", "▍", "▌", "▋", "▊", "▉"}
  @vertical_fractions {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

  def render(data, series, width, mode, max_value) do
    {xs, series} = Breeze.Charts.Data.prepare(data, series)
    categories = Enum.map(xs, &to_string/1)
    validate!(series, width, mode, max_value)

    if series == [] or categories == [] do
      []
    else
      groups = Enum.zip(Enum.map(series, & &1.values)) |> Enum.map(&Tuple.to_list/1)
      values = if mode == :stacked, do: Enum.map(groups, &Enum.sum/1), else: List.flatten(groups)
      maximum = Enum.max(values)
      scale = max_value || if(maximum == 0, do: 1, else: maximum)

      labels =
        if mode == :grouped do
          for category <- categories, item <- series, do: category <> " / " <> item.name
        else
          categories
        end

      columns = columns(labels, values, width)

      rows =
        Enum.zip(categories, groups)
        |> Enum.map(fn {category, group} ->
          rows(category, group, series, mode, scale, columns)
        end)
        |> Enum.intersperse(if(mode == :grouped, do: [[]], else: []))
        |> Enum.concat()

      (legend(series, width) ++ [[]] ++ rows)
      |> Enum.intersperse([TextSpan.new("\n")])
      |> List.flatten()
    end
  end

  def render_vertical(data, series, width, height, mode, max_value) do
    {xs, series} = Breeze.Charts.Data.prepare(data, series)
    categories = Enum.map(xs, &to_string/1)
    validate!(series, width, mode, max_value)

    unless is_integer(height) and height > 0 do
      raise ArgumentError, "bar_chart height must be a positive integer"
    end

    if series == [] or categories == [] do
      []
    else
      groups = Enum.zip(Enum.map(series, & &1.values)) |> Enum.map(&Tuple.to_list/1)
      values = if mode == :stacked, do: Enum.map(groups, &Enum.sum/1), else: List.flatten(groups)
      maximum = Enum.max(values)
      scale = max_value || if(maximum == 0, do: 1, else: maximum)
      legend = legend(series, width)
      label_width = string_length(format(scale))
      plot_width = width - label_width - 1
      plot_height = height - length(legend) - 2
      slot_width = div(max(plot_width, 0), length(categories))
      group_width = slot_width - if(length(categories) > 1, do: 1, else: 0)
      bar_count = if mode == :grouped, do: length(series), else: 1

      rows =
        if plot_height < 1 or group_width < bar_count * 2 - 1 do
          Enum.take(legend, height)
        else
          bar_width = div(group_width - bar_count + 1, bar_count)

          plot =
            for bottom <- (plot_height - 1)..0//-1 do
              label = if bottom == plot_height - 1, do: format(scale), else: ""

              bars =
                Enum.flat_map(groups, fn group ->
                  vertical_group(group, series, mode, scale, plot_height, bottom, bar_width)
                  |> center_spans(slot_width)
                end)

              [TextSpan.new(String.pad_leading(label, label_width) <> "│")] ++
                bars ++ [TextSpan.new(String.duplicate(" ", rem(plot_width, length(groups))))]
            end

          labels = Enum.map(categories, &center(&1, slot_width)) |> Enum.join()

          plot ++
            [
              [
                TextSpan.new(
                  String.pad_leading("0", label_width) <> "└" <> String.duplicate("─", plot_width)
                )
              ],
              [TextSpan.new(String.duplicate(" ", label_width + 1) <> labels)]
            ] ++ legend
        end

      rows |> Enum.intersperse([TextSpan.new("\n")]) |> List.flatten()
    end
  end

  defp vertical_group(values, series, :grouped, scale, height, bottom, bar_width) do
    Enum.zip(values, series)
    |> Enum.map(fn {value, item} ->
      ticks = round(min(value / scale, 1) * height * 8)
      glyph = elem(@vertical_fractions, min(max(ticks - bottom * 8, 0), 8))
      TextSpan.new(String.duplicate(glyph, bar_width), %{foreground_color: item.color})
    end)
    |> Enum.intersperse(TextSpan.new(" "))
  end

  defp vertical_group(values, series, :stacked, scale, height, bottom, bar_width) do
    {segments, _total} =
      Enum.zip(values, series)
      |> Enum.map_reduce(0, fn {value, item}, total ->
        start = round(min(total / scale, 1) * height)
        finish = round(min((total + value) / scale, 1) * height)
        {{start, finish, item.color}, total + value}
      end)

    case Enum.find(segments, fn {start, finish, _color} -> bottom >= start and bottom < finish end) do
      {_start, _finish, color} ->
        [TextSpan.new(String.duplicate("█", bar_width), %{foreground_color: color})]

      nil ->
        [TextSpan.new(String.duplicate(" ", bar_width))]
    end
  end

  defp center_spans(spans, width) do
    used = Enum.reduce(spans, 0, fn span, count -> count + string_length(span.text) end)
    left = div(width - used, 2)

    [TextSpan.new(String.duplicate(" ", left))] ++
      spans ++ [TextSpan.new(String.duplicate(" ", width - used - left))]
  end

  defp center(text, width) do
    text = Text.truncate(text, width)
    padding = width - string_length(text)

    String.duplicate(" ", div(padding, 2)) <>
      text <> String.duplicate(" ", padding - div(padding, 2))
  end

  defp validate!(series, width, mode, max_value) do
    unless is_integer(width) and width > 0 do
      raise ArgumentError, "bar_chart width must be a positive integer"
    end

    unless mode in [:grouped, :stacked] do
      raise ArgumentError, "bar_chart mode must be :grouped or :stacked"
    end

    unless is_nil(max_value) or (is_number(max_value) and max_value > 0) do
      raise ArgumentError, "bar_chart max must be a positive number"
    end

    Enum.each(series, fn item ->
      unless Enum.all?(item.values, &(&1 >= 0)) do
        raise ArgumentError, "bar_chart values must be nonnegative numbers"
      end
    end)
  end

  defp columns(_categories, _values, width) when width < 5, do: {0, width, 0}

  defp columns(categories, values, width) do
    labels = categories |> Enum.map(&string_length/1) |> Enum.max()
    values = values |> Enum.map(&(format(&1) |> string_length())) |> Enum.max()
    value_width = if values <= div(width, 2), do: values, else: 0
    gutters = if value_width == 0, do: 1, else: 2
    label_width = min(min(labels, div(width, 3)), width - value_width - gutters - 1)
    {label_width, width - label_width - value_width - gutters, value_width}
  end

  defp rows(category, values, series, :grouped, scale, columns) do
    Enum.zip(values, series)
    |> Enum.map(fn {value, item} ->
      label = category <> " / " <> item.name
      {_label_width, plot_width, _value_width} = columns
      ticks = round(min(value / scale, 1) * plot_width * 8)
      bar = String.duplicate("█", div(ticks, 8)) <> elem(@fractions, rem(ticks, 8))
      row(label, value, [TextSpan.new(bar, %{foreground_color: item.color})], columns)
    end)
  end

  defp rows(category, values, series, :stacked, scale, columns) do
    {_label_width, plot_width, _value_width} = columns

    {bars, _total} =
      Enum.zip(values, series)
      |> Enum.map_reduce(0, fn {value, item}, total ->
        start = round(min(total / scale, 1) * plot_width)
        finish = round(min((total + value) / scale, 1) * plot_width)

        span =
          TextSpan.new(String.duplicate("█", finish - start), %{foreground_color: item.color})

        {span, total + value}
      end)

    [row(category, Enum.sum(values), bars, columns)]
  end

  defp row(_label, _value, bars, {0, _plot_width, 0}), do: bars

  defp row(label, value, bars, {label_width, plot_width, value_width}) do
    bar_width = Enum.reduce(bars, 0, fn span, acc -> acc + string_length(span.text) end)

    value_spans =
      if value_width == 0 do
        []
      else
        [
          TextSpan.new(String.duplicate(" ", plot_width - bar_width) <> " "),
          TextSpan.new(pad(format(value), value_width))
        ]
      end

    [TextSpan.new(pad(label, label_width) <> " ")] ++ bars ++ value_spans
  end

  defp legend(series, width) do
    {lines, current, _used} =
      Enum.reduce(series, {[], [], 0}, fn item, {lines, current, used} ->
        text = Text.truncate("■ " <> item.name, width)
        size = string_length(text)
        span = TextSpan.new(text, %{foreground_color: item.color})

        cond do
          current == [] ->
            {lines, [span], size}

          used + 2 + size <= width ->
            {lines, current ++ [TextSpan.new("  "), span], used + 2 + size}

          true ->
            {[current | lines], [span], size}
        end
      end)

    Enum.reverse([current | lines])
  end

  defp pad(text, width) do
    text = Text.truncate(text, width)
    text <> String.duplicate(" ", width - string_length(text))
  end

  defp format(value) when is_integer(value), do: Integer.to_string(value)
  defp format(value), do: Float.to_string(value)
end
