defmodule Breeze.Chart do
  @moduledoc """
  Chart components for Breeze views.

  The namespace is intentionally separate from `Breeze.Blocks` so these
  components can be extracted later without involving the server/runtime layer.
  """

  use Breeze.View

  attr :data, :list, required: true
  attr :summary, :any, default: :max
  attr :min, :any, default: nil
  attr :max, :any, default: nil
  attr :missing, :string, default: " "
  attr :axis, :boolean, default: false
  attr :show_axis, :boolean, default: nil
  attr :axis_color, :any, default: nil
  attr :axis_style, :any, default: nil
  attr :empty, :string, default: "No data"
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :rest, :global

  slot :axis do
    attr :class, :string
    attr :color, :any
    attr :style, :any
  end

  def sparkline(assigns) do
    assigns =
      assigns
      |> assign(
        class: Breeze.Blocks.merge_class("height-1 overflow-hidden bg-panel", assigns[:class])
      )
      |> assign(content: Breeze.Chart.Sparkline.render(assigns))

    ~H"""
    <box class={@class} style={Breeze.Blocks.inline_style(assigns)} {@rest}>{@content}</box>
    """
  end

  attr :data, :list, required: true
  attr :label_key, :any, default: :label
  attr :value_key, :any, default: :value
  attr :orientation, :any, default: :vertical
  attr :min, :any, default: nil
  attr :max, :any, default: nil
  attr :missing, :any, default: :zero
  attr :axis, :boolean, default: false
  attr :show_axis, :boolean, default: nil
  attr :axis_color, :any, default: nil
  attr :axis_style, :any, default: nil
  attr :empty, :string, default: "No data"
  attr :virtual, :any, default: false
  attr :cache_key, :any, default: nil
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :rest, :global

  slot :axis do
    attr :class, :string
    attr :color, :any
    attr :style, :any
  end

  def bar_chart(assigns) do
    assigns =
      assigns
      |> assign(
        class:
          Breeze.Blocks.merge_class(
            "width-full height-8 overflow-hidden bg-panel",
            assigns[:class]
          )
      )
      |> assign(content: Breeze.Chart.BarChart.render(assigns))

    ~H"""
    <box class={@class} style={Breeze.Blocks.inline_style(assigns)} {@rest}>{@content}</box>
    """
  end

  attr :series, :list, default: []
  attr :x_bounds, :any, default: :auto
  attr :y_bounds, :any, default: :auto
  attr :axis, :boolean, default: false
  attr :show_axis, :boolean, default: nil
  attr :axis_color, :any, default: nil
  attr :axis_style, :any, default: nil
  attr :legend, :boolean, default: false
  attr :empty, :string, default: "No data"
  attr :virtual, :any, default: false
  attr :cache_key, :any, default: nil
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :rest, :global

  slot :axis do
    attr :class, :string
    attr :color, :any
    attr :style, :any
  end

  slot :x_axis do
    attr :title, :string
    attr :labels, :list
    attr :ticks, :integer
    attr :format, :any
    attr :bounds, :any
    attr :class, :string
    attr :color, :any
    attr :style, :any
  end

  slot :y_axis do
    attr :title, :string
    attr :labels, :list
    attr :ticks, :integer
    attr :format, :any
    attr :bounds, :any
    attr :class, :string
    attr :color, :any
    attr :style, :any
  end

  slot :dataset do
    attr :data, :list, required: true
    attr :name, :string
    attr :marker, :string
    attr :class, :string
    attr :color, :any
    attr :style, :any
  end

  def line_chart(assigns) do
    assigns =
      assigns
      |> assign(
        class:
          Breeze.Blocks.merge_class(
            "width-full height-10 overflow-hidden bg-panel",
            assigns[:class]
          )
      )
      |> assign(content: Breeze.Chart.LineChart.render(assigns))

    ~H"""
    <box class={@class} style={Breeze.Blocks.inline_style(assigns)} {@rest}>{@content}</box>
    """
  end
end

defmodule Breeze.Chart.Common do
  @moduledoc false

  alias BackBreeze.TextSpan

  @text_style_keys [
    :foreground_color,
    :background_color,
    :bold,
    :italic,
    :reverse
  ]

  def dimensions(assigns, defaults) do
    resolved = Breeze.Style.resolve_dimensions(assigns[:class], assigns[:style])

    %{
      width: width_or_default(resolved.width, defaults.width),
      height: integer_or_default(resolved.height, defaults.height)
    }
  end

  def point_value(%{value: value}), do: number_or_nil(value)
  def point_value(value), do: number_or_nil(value)

  def number_or_nil(value) when is_number(value), do: value
  def number_or_nil(_value), do: nil

  def value_from(row, key, default \\ nil)

  def value_from(row, index, _default) when is_tuple(row) and is_integer(index),
    do: elem(row, index)

  def value_from(row, key, default) when is_map(row), do: Map.get(row, key, default)

  def value_from(row, key, default) when is_list(row) do
    if Keyword.keyword?(row), do: Keyword.get(row, key, default), else: default
  end

  def value_from({label, _value}, :label, _default), do: label
  def value_from({label, _value}, 0, _default), do: label
  def value_from({_label, value}, :value, _default), do: value
  def value_from({_label, value}, 1, _default), do: value
  def value_from(_row, _key, default), do: default

  def bounds(values, explicit_min, explicit_max, constant \\ :middle) do
    values = Enum.filter(values, &is_number/1)

    cond do
      values == [] ->
        {0, 1}

      true ->
        min_value = explicit_min || Enum.min(values)
        max_value = explicit_max || Enum.max(values)

        if min_value == max_value do
          case constant do
            :full -> {0, max(max_value, 1)}
            _ -> {min_value - 1, max_value + 1}
          end
        else
          {min_value, max_value}
        end
    end
  end

  def ratio(nil, _min, _max), do: nil
  def ratio(_value, min, max) when min == max, do: 0.5

  def ratio(value, min, max) do
    ((value - min) / (max - min))
    |> max(0.0)
    |> min(1.0)
  end

  def maybe_virtual(false, _kind, _assigns, content, _line_fun), do: content
  def maybe_virtual(nil, _kind, _assigns, content, _line_fun), do: content

  def maybe_virtual(_virtual, kind, assigns, _content, line_fun) do
    dims = dimensions(assigns, %{width: 1, height: 1})
    virtual_content(kind, assigns, intrinsic_width(dims.width), dims.height, line_fun)
  end

  def virtual_content(kind, assigns, intrinsic_width, height, line_fun) do
    cache_key = assigns[:cache_key] || {__MODULE__, kind, :erlang.phash2(assigns)}

    BackBreeze.VirtualText.lazy(
      cache_key: cache_key,
      intrinsic_width: intrinsic_width,
      line_count_fn: fn _width -> height end,
      slice_fn: fn start_line, count, width ->
        line_fun.(max(width, 1))
        |> Enum.slice(start_line, count)
      end
    )
  end

  def flexible_width?(width), do: width in [:full, :screen]
  def virtual_enabled?(assigns), do: Map.get(assigns, :virtual) not in [nil, false]

  def style_for(%{style: %BackBreeze.Style{} = style}), do: Map.from_struct(style)
  def style_for(%{style: style}) when is_map(style), do: style
  def style_for(%{style: _style}), do: %{}
  def style_for(_value), do: %{}

  def axis_style(assigns) do
    text_style(assigns, first_slot_attrs(assigns, :axis), :axis_color, :axis_style)
  end

  def text_style(assigns, attrs, color_key \\ :color, style_key \\ :style) do
    color = value_from(attrs, :color, fallback_assign(assigns, color_key))
    style = value_from(attrs, :style, fallback_assign(assigns, style_key))

    Breeze.Style.empty()
    |> Breeze.Style.put_class(value_from(attrs, :class, nil))
    |> Breeze.Style.put_style(style)
    |> Breeze.Style.put_style(color_style(color))
    |> Breeze.Style.to_element(
      theme: chart_theme(assigns),
      apply_theme_defaults: false
    )
    |> Map.get(:style)
    |> style_struct_to_map()
    |> Map.take(@text_style_keys)
    |> reject_empty_style_values()
  end

  def lines_to_content(lines, styled?) do
    if styled? do
      lines
      |> Enum.map(&line_to_spans/1)
      |> Enum.intersperse([TextSpan.new("\n")])
      |> List.flatten()
    else
      lines
      |> Enum.map(&line_to_string/1)
      |> Enum.join("\n")
    end
  end

  def text_width(text), do: BackBreeze.Ucwidth.width(to_string(text))

  def truthy?(value), do: value in [true, "", "true", :show, "show", :visible, "visible"]

  def axis_enabled?(assigns) do
    case Map.get(assigns, :show_axis) do
      nil ->
        truthy?(Map.get(assigns, :axis)) or slot_present?(assigns, :axis) or
          slot_present?(assigns, :x_axis) or slot_present?(assigns, :y_axis)

      value ->
        truthy?(value)
    end
  end

  def virtual_line(line) when is_binary(line), do: line

  def virtual_line(line) when is_list(line) do
    if Enum.any?(line, &match?(%TextSpan{}, &1)) do
      Enum.map(line, fn
        %TextSpan{text: text, style: style} -> {text, style}
        text when is_binary(text) -> {text, %{}}
      end)
    else
      line_to_string(line)
    end
  end

  def first_slot_attrs(assigns, key) do
    assigns
    |> Map.get(key, [])
    |> List.wrap()
    |> List.first(%{})
  end

  def slot_present?(assigns, key) do
    case Map.get(assigns, key) do
      [_ | _] -> true
      _ -> false
    end
  end

  defp fallback_assign(_assigns, nil), do: nil
  defp fallback_assign(assigns, key), do: Map.get(assigns, key)

  defp line_to_spans(line) when is_binary(line), do: [TextSpan.new(line)]

  defp line_to_spans(line) when is_list(line) do
    Enum.map(line, fn
      %TextSpan{} = span -> span
      text when is_binary(text) -> TextSpan.new(text)
    end)
  end

  defp line_to_string(line) when is_binary(line), do: line
  defp line_to_string(line) when is_list(line), do: Enum.join(line, "")

  defp color_style(nil), do: nil
  defp color_style(color), do: %{foreground_color: color}

  defp chart_theme(%{breeze: %{theme: theme}}), do: theme
  defp chart_theme(%{breeze: breeze}) when is_map(breeze), do: Map.get(breeze, "theme")
  defp chart_theme(_assigns), do: nil

  defp style_struct_to_map(%BackBreeze.Style{} = style), do: Map.from_struct(style)
  defp style_struct_to_map(style) when is_map(style), do: style
  defp style_struct_to_map(_style), do: %{}

  defp reject_empty_style_values(style) do
    Map.reject(style, fn {_key, value} -> is_nil(value) or value == false end)
  end

  defp width_or_default(value, _default) when value in [:full, :screen], do: value
  defp width_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp width_or_default(_value, default), do: default

  defp intrinsic_width(width) when is_integer(width) and width > 0, do: width
  defp intrinsic_width(_width), do: 1

  defp integer_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp integer_or_default(_value, default), do: default
end

defmodule Breeze.Chart.Sparkline do
  @moduledoc false

  alias BackBreeze.TextSpan
  alias Breeze.Chart.Common

  @blocks ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

  def render(assigns) do
    points = List.wrap(assigns[:data])
    dims = Common.dimensions(assigns, %{width: length(points), height: 1})

    if Common.flexible_width?(dims.width) do
      Common.virtual_content(:sparkline, assigns, max(length(points), 1), dims.height, fn width ->
        points
        |> render_lines(%{dims | width: width}, assigns)
        |> Enum.map(&Common.virtual_line/1)
      end)
    else
      lines = render_lines(points, dims, assigns)
      styled? = Enum.any?(List.flatten(lines), &match?(%TextSpan{}, &1))
      Common.lines_to_content(lines, styled?)
    end
  end

  defp render_lines(points, dims, assigns) do
    axis? = Common.axis_enabled?(assigns) and dims.height >= 2
    plot_width = if(axis?, do: max(dims.width - 1, 1), else: dims.width)
    buckets = bucket(points, max(plot_width, 1), assigns[:summary] || :max)
    values = Enum.map(buckets, &Common.point_value/1)

    if Enum.all?(values, &is_nil/1) do
      [assigns[:empty] || "No data"]
    else
      {min_value, max_value} = Common.bounds(values, assigns[:min], assigns[:max])

      buckets
      |> render_buckets(min_value, max_value, assigns[:missing] || " ")
      |> lines_with_axis(axis?, dims.width, Common.axis_style(assigns))
    end
  end

  defp bucket([], width, _summary), do: List.duplicate(nil, width)

  defp bucket(points, width, _summary) when length(points) <= width do
    last_index = length(points) - 1
    span = max(width - 1, 1)

    Enum.map(0..(width - 1), fn index ->
      source_index = round(index * last_index / span)
      Enum.at(points, source_index)
    end)
  end

  defp bucket(points, width, summary) do
    total = length(points)

    Enum.map(0..(width - 1), fn index ->
      start_index = floor(index * total / width)
      end_index = floor((index + 1) * total / width) - 1

      points
      |> Enum.slice(start_index..max(start_index, end_index))
      |> summarize(summary)
    end)
  end

  defp summarize(points, summary) do
    values = points |> Enum.map(&Common.point_value/1) |> Enum.filter(&is_number/1)

    cond do
      values == [] -> nil
      is_function(summary, 1) -> summary.(values)
      summary == :min -> Enum.min(values)
      summary == :mean -> Enum.sum(values) / length(values)
      true -> Enum.max(values)
    end
  end

  defp render_buckets(buckets, min_value, max_value, missing) do
    styled? = Enum.any?(buckets, &(Common.style_for(&1) != %{}))

    rendered =
      Enum.map(buckets, fn point ->
        value = Common.point_value(point)
        char = value_to_char(value, min_value, max_value, missing)
        style = Common.style_for(point)

        if styled?, do: TextSpan.new(char, style), else: char
      end)

    if styled?, do: rendered, else: Enum.join(rendered, "")
  end

  defp value_to_char(nil, _min, _max, missing), do: missing

  defp value_to_char(value, min_value, max_value, _missing) do
    ratio = Common.ratio(value, min_value, max_value)
    index = round(ratio * (length(@blocks) - 1))
    Enum.at(@blocks, index)
  end

  defp lines_with_axis(content, false, _width, _axis_style), do: [content]

  defp lines_with_axis(content, true, width, axis_style) when is_binary(content) do
    [
      [TextSpan.new("│", axis_style), TextSpan.new(content)],
      [TextSpan.new(axis_line(width), axis_style)]
    ]
  end

  defp lines_with_axis(content, true, width, axis_style) when is_list(content) do
    [
      [TextSpan.new("│", axis_style) | content],
      [TextSpan.new(axis_line(width), axis_style)]
    ]
  end

  defp axis_line(width), do: "└" <> String.duplicate("─", max(width - 1, 0))
end

defmodule Breeze.Chart.BarChart do
  @moduledoc false

  alias BackBreeze.TextSpan
  alias Breeze.Chart.Common

  def render(assigns) do
    rows = normalize_rows(assigns)
    dims = Common.dimensions(assigns, %{width: inferred_width(rows), height: 8})

    if Common.flexible_width?(dims.width) or Common.virtual_enabled?(assigns) do
      Common.virtual_content(:bar_chart, assigns, inferred_width(rows), dims.height, fn width ->
        rows
        |> render_lines(width, dims.height, assigns)
        |> Enum.map(&Common.virtual_line/1)
      end)
    else
      render_content(rows, dims.width, dims.height, assigns)
    end
  end

  defp render_content(rows, width, height, assigns) do
    lines = render_lines(rows, width, height, assigns)
    styled? = Enum.any?(List.flatten(lines), &match?(%TextSpan{}, &1))
    if styled?, do: Common.lines_to_content(lines, true), else: lines
  end

  defp normalize_rows(assigns) do
    label_key = assigns[:label_key] || :label
    value_key = assigns[:value_key] || :value

    assigns[:data]
    |> List.wrap()
    |> Enum.map(fn row ->
      %{
        label: Common.value_from(row, label_key, ""),
        value: Common.value_from(row, value_key, nil),
        style: Common.style_for(row)
      }
    end)
  end

  defp render_lines([], _width, _height, assigns), do: [assigns[:empty] || "No data"]

  defp render_lines(rows, width, height, assigns) do
    if (assigns[:orientation] || :vertical) in [:horizontal, "horizontal"] do
      render_horizontal_lines(rows, width, height, assigns)
    else
      render_vertical_lines(rows, width, height, assigns)
    end
  end

  defp render_horizontal_lines(rows, width, height, assigns) do
    axis? = Common.axis_enabled?(assigns)
    axis_style = Common.axis_style(assigns)
    values = Enum.map(rows, &Common.number_or_nil(&1.value))
    {min_value, max_value} = Common.bounds(values, assigns[:min], assigns[:max], :full)
    label_width = rows |> Enum.map(&Common.text_width(&1.label)) |> Enum.max(fn -> 0 end)
    bar_width = max(width - label_width - 1, 1)
    row_height = if(axis?, do: max(height - 1, 1), else: height)

    chart_rows =
      rows
      |> Enum.take(row_height)
      |> Enum.map(fn row ->
        value = Common.number_or_nil(row.value) || 0
        filled = round(Common.ratio(value, min_value, max_value) * bar_width)
        label = row.label |> to_string() |> String.pad_trailing(label_width)
        fit_line(label <> " " <> String.duplicate("█", filled), width)
      end)

    if axis?, do: chart_rows ++ [styled_axis_line(width, axis_style)], else: chart_rows
  end

  defp render_vertical_lines(rows, width, height, assigns) do
    axis? = Common.axis_enabled?(assigns)
    axis_style = Common.axis_style(assigns)
    values = Enum.map(rows, &Common.number_or_nil(&1.value))
    {min_value, max_value} = Common.bounds(values, assigns[:min], assigns[:max], :full)
    bar_count = max(length(rows), 1)
    plot_width = if(axis?, do: max(width - 1, 1), else: width)
    slot_width = max(div(plot_width, bar_count), 1)
    bar_width = max(slot_width - 1, 1)
    plot_height = if(axis?, do: max(height - 2, 1), else: max(height - 1, 1))

    bars =
      Enum.map(rows, fn row ->
        value = Common.number_or_nil(row.value) || 0
        round(Common.ratio(value, min_value, max_value) * plot_height)
      end)

    plot =
      for y <- (plot_height - 1)..0//-1 do
        rows
        |> Enum.with_index()
        |> Enum.map(fn {_row, index} ->
          if Enum.at(bars, index) > y do
            String.duplicate("█", bar_width)
          else
            String.duplicate(" ", bar_width)
          end
        end)
        |> Enum.intersperse(" ")
        |> Enum.join()
        |> maybe_prepend_axis(axis?, "│", axis_style)
        |> fit_line(width)
      end

    labels =
      rows
      |> Enum.map(fn row ->
        row.label |> to_string() |> String.slice(0, bar_width) |> String.pad_trailing(bar_width)
      end)
      |> Enum.intersperse(" ")
      |> Enum.join()
      |> maybe_prepend_axis(axis?, " ", %{})
      |> fit_line(width)

    if axis? do
      plot ++ [styled_axis_line(width, axis_style), labels]
    else
      plot ++ [labels]
    end
  end

  defp maybe_prepend_axis(line, true, marker, axis_style) when axis_style == %{},
    do: marker <> line

  defp maybe_prepend_axis(line, true, marker, axis_style),
    do: [TextSpan.new(marker, axis_style), TextSpan.new(line)]

  defp maybe_prepend_axis(line, false, _marker, _axis_style), do: line

  defp axis_line(width), do: "└" <> String.duplicate("─", max(width - 1, 0))

  defp styled_axis_line(width, axis_style) when axis_style == %{}, do: axis_line(width)
  defp styled_axis_line(width, axis_style), do: [TextSpan.new(axis_line(width), axis_style)]

  defp fit_line(line, width) when is_binary(line) do
    line
    |> String.slice(0, width)
    |> String.pad_trailing(width)
  end

  defp fit_line(line, width) when is_list(line) do
    line_width =
      Enum.reduce(line, 0, fn
        %TextSpan{text: text}, acc -> acc + String.length(text)
        text, acc when is_binary(text) -> acc + String.length(text)
      end)

    if line_width < width do
      line ++ [TextSpan.new(String.duplicate(" ", width - line_width))]
    else
      line
    end
  end

  defp inferred_width([]), do: 12

  defp inferred_width(rows) do
    rows
    |> Enum.map(&Common.text_width(&1.label))
    |> Enum.sum()
    |> Kernel.+(max(length(rows) - 1, 0))
    |> max(12)
  end
end

defmodule Breeze.Chart.LineChart do
  @moduledoc false

  alias BackBreeze.TextSpan
  alias Breeze.Chart.Common

  @tick_label_gap 2

  def render(assigns) do
    series = normalize_series(assigns)
    points = Enum.flat_map(series, & &1.points)

    if points == [] do
      assigns[:empty] || "No data"
    else
      dims = Common.dimensions(assigns, %{width: 40, height: 10})

      if Common.flexible_width?(dims.width) or Common.virtual_enabled?(assigns) do
        Common.virtual_content(:line_chart, assigns, 40, dims.height, fn width ->
          series
          |> render_lines(width, dims.height, assigns)
          |> Enum.map(&Common.virtual_line/1)
        end)
      else
        render_content(series, dims.width, dims.height, assigns)
      end
    end
  end

  defp normalize_series(assigns) do
    assigns
    |> series_entries()
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.map(fn {series, index} ->
      data = Common.value_from(series, :data, series)

      %{
        name: Common.value_from(series, :name, "series-#{index + 1}"),
        style: Common.text_style(assigns, series, nil, nil),
        marker: Common.value_from(series, :marker, marker_for(index)),
        points: normalize_points(data)
      }
    end)
  end

  defp series_entries(assigns) do
    List.wrap(assigns[:series]) ++ List.wrap(assigns[:dataset])
  end

  defp normalize_points(data) do
    data
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.flat_map(fn {point, index} ->
      case point do
        {x, y} when is_number(x) and is_number(y) -> [%{x: x, y: y}]
        %{x: x, y: y} when is_number(x) and is_number(y) -> [%{x: x, y: y}]
        y when is_number(y) -> [%{x: index, y: y}]
        _ -> []
      end
    end)
  end

  defp render_content(series, width, height, assigns) do
    lines = render_lines(series, width, height, assigns)
    styled? = Enum.any?(List.flatten(lines), &match?(%TextSpan{}, &1))
    Common.lines_to_content(lines, styled?)
  end

  defp render_lines(series, width, height, assigns) do
    points = Enum.flat_map(series, & &1.points)
    x_axis = axis_spec(assigns, :x_axis)
    y_axis = axis_spec(assigns, :y_axis)

    {min_x, max_x} =
      axis_bounds(Enum.map(points, & &1.x), x_axis.bounds || assigns[:x_bounds] || :auto)

    {min_y, max_y} =
      axis_bounds(Enum.map(points, & &1.y), y_axis.bounds || assigns[:y_bounds] || :auto)

    axis? = Common.axis_enabled?(assigns)
    axis_style = Common.axis_style(assigns)
    x_axis = %{x_axis | style: axis_slot_style(assigns, :x_axis, axis_style)}
    y_axis = %{y_axis | style: axis_slot_style(assigns, :y_axis, axis_style)}
    axis_columns = if(axis?, do: 1, else: 0)
    axis_rows = if(axis?, do: 1, else: 0)
    x_label_rows = if(axis? and x_axis_labelled?(x_axis), do: 1, else: 0)
    available_plot_height = max(height - axis_rows - x_label_rows, 1)
    y_gutter = if(axis?, do: y_gutter_width(y_axis, min_y, max_y, available_plot_height), else: 0)
    plot_width = max(width - y_gutter - axis_columns, 1)
    plot_height = max(height - axis_rows - x_label_rows, 1)

    grid =
      for _y <- 1..plot_height do
        for _x <- 1..plot_width do
          nil
        end
      end

    grid =
      Enum.reduce(series, grid, fn item, acc ->
        Enum.reduce(item.points, acc, fn point, point_acc ->
          x = coordinate(point.x, min_x, max_x, plot_width)
          y = plot_height - 1 - coordinate(point.y, min_y, max_y, plot_height)
          put_cell(point_acc, x, y, {item.marker, item.style})
        end)
      end)

    grid
    |> Enum.map(fn row ->
      styled? =
        Enum.any?(row, fn
          {_marker, style} -> style != %{}
          _ -> false
        end)

      Enum.map(row, fn
        nil -> if styled?, do: TextSpan.new(" "), else: " "
        {marker, style} -> if styled?, do: TextSpan.new(marker, style), else: marker
      end)
    end)
    |> maybe_add_axis(axis?, width, height, axis_style, x_axis, y_axis, y_gutter, %{
      min_x: min_x,
      max_x: max_x,
      min_y: min_y,
      max_y: max_y,
      plot_width: plot_width,
      plot_height: plot_height,
      x_label_rows: x_label_rows
    })
  end

  defp maybe_add_axis(
         lines,
         false,
         _width,
         _height,
         _axis_style,
         _x_axis,
         _y_axis,
         _y_gutter,
         _ctx
       ),
       do: lines

  defp maybe_add_axis(lines, true, width, height, axis_style, x_axis, y_axis, y_gutter, ctx) do
    plot_rows = max(height - 1 - ctx.x_label_rows, 1)
    axis_width = max(width - y_gutter, 1)

    axis_row = [
      TextSpan.new(String.duplicate(" ", y_gutter)) | axis_row(axis_width, axis_style, x_axis)
    ]

    lines
    |> Enum.take(plot_rows)
    |> Enum.with_index()
    |> Enum.map(fn {line, row_index} ->
      line
      |> fit_line(ctx.plot_width)
      |> prepend_axis("│", y_axis.style)
      |> prepend_y_label(y_axis, y_gutter, row_index, ctx)
      |> fit_line(width)
    end)
    |> Kernel.++([fit_line(axis_row, width)])
    |> maybe_append_x_labels(width, x_axis, y_gutter, ctx)
  end

  defp prepend_axis(line, marker, axis_style), do: [TextSpan.new(marker, axis_style) | line]

  defp prepend_y_label(line, _y_axis, 0, _row_index, _ctx), do: line

  defp prepend_y_label(line, y_axis, y_gutter, row_index, ctx) do
    label = y_label_for_row(y_axis, row_index, ctx)

    [
      TextSpan.new(
        label |> String.slice(0, y_gutter) |> String.pad_leading(y_gutter),
        y_axis.style
      )
      | line
    ]
  end

  defp axis_row(axis_width, axis_style, x_axis) do
    line = "└" <> String.duplicate("─", max(axis_width - 1, 0))

    line =
      case x_axis.title do
        nil -> line
        "" -> line
        title -> overlay_center(line, to_string(title))
      end

    [TextSpan.new(line, axis_style)]
  end

  defp maybe_append_x_labels(lines, _width, _x_axis, _y_gutter, %{x_label_rows: 0}), do: lines

  defp maybe_append_x_labels(lines, width, x_axis, y_gutter, ctx) do
    labels = x_label_row(x_axis, ctx)
    prefix = String.duplicate(" ", y_gutter + 1)

    row =
      [TextSpan.new(prefix), TextSpan.new(labels, x_axis.style)]
      |> fit_line(width)

    lines ++ [row]
  end

  defp axis_bounds(values, :auto), do: Common.bounds(values, nil, nil)
  defp axis_bounds(values, nil), do: Common.bounds(values, nil, nil)
  defp axis_bounds(_values, {min, max}) when is_number(min) and is_number(max), do: {min, max}

  defp coordinate(_value, min, max, _size) when min == max, do: 0

  defp coordinate(value, min, max, size) do
    value
    |> Common.ratio(min, max)
    |> Kernel.*(max(size - 1, 0))
    |> round()
  end

  defp put_cell(grid, x, y, value) when y >= 0 do
    List.update_at(grid, y, fn row -> List.replace_at(row, x, value) end)
  end

  defp put_cell(grid, _x, _y, _value), do: grid

  defp marker_for(index), do: Enum.at(["•", "×", "+", "*"], rem(index, 4))

  defp axis_spec(assigns, key) do
    attrs = Common.first_slot_attrs(assigns, key)

    present? = Common.slot_present?(assigns, key)
    labels = Common.value_from(attrs, :labels, [])
    ticks = Common.value_from(attrs, :ticks, nil)

    %{
      present?: present?,
      title: Common.value_from(attrs, :title, nil),
      labels: labels,
      ticks: default_axis_ticks(present?, labels, ticks),
      format: Common.value_from(attrs, :format, nil),
      bounds: Common.value_from(attrs, :bounds, nil),
      style: %{}
    }
  end

  defp axis_slot_style(assigns, key, fallback) do
    attrs = Common.first_slot_attrs(assigns, key)
    style = Common.text_style(assigns, attrs, nil, nil)
    if style == %{}, do: fallback, else: style
  end

  defp x_axis_labelled?(%{labels: labels, ticks: ticks}) do
    labels != [] or ticks == :auto or ticks == "auto" or (is_integer(ticks) and ticks > 0)
  end

  defp y_gutter_width(%{present?: false}, _min_y, _max_y, _plot_height), do: 0

  defp y_gutter_width(y_axis, min_y, max_y, plot_height) do
    labels = axis_labels(y_axis, min_y, max_y, plot_height)

    top_label =
      labels |> Enum.max_by(fn {value, _label} -> value end, fn -> nil end) |> label_text()

    label_widths = Enum.map(labels, fn {_value, label} -> String.length(label) end)
    title_width = join_label(y_axis.title, top_label) |> String.length()

    [title_width | label_widths]
    |> Enum.max(fn -> 0 end)
  end

  defp y_label_for_row(y_axis, row_index, ctx) do
    labels =
      y_axis
      |> axis_labels(ctx.min_y, ctx.max_y, ctx.plot_height)
      |> Enum.map(fn {value, label} ->
        row = ctx.plot_height - 1 - coordinate(value, ctx.min_y, ctx.max_y, ctx.plot_height)
        {row, label}
      end)
      |> Map.new()

    label = Map.get(labels, row_index, "")
    if row_index == 0, do: join_label(y_axis.title, label), else: label
  end

  defp x_label_row(x_axis, ctx) do
    labels =
      x_axis
      |> axis_labels(ctx.min_x, ctx.max_x, {:x, ctx.plot_width})
      |> Enum.map(fn {value, label} ->
        column = coordinate(value, ctx.min_x, ctx.max_x, ctx.plot_width)
        {column, label}
      end)
      |> spaced_x_labels(ctx.plot_width)

    Enum.reduce(labels, String.duplicate(" ", ctx.plot_width), fn {column, label}, acc ->
      overlay_at(acc, label, column)
    end)
  end

  defp spaced_x_labels(labels, width) do
    labels =
      labels
      |> Enum.sort_by(fn {column, _label} -> column end)
      |> Enum.map(fn {column, label} -> {column, to_string(label)} end)

    case labels do
      [] ->
        []

      [_one] ->
        Enum.map(labels, &fit_x_label(&1, width))

      [first | rest] ->
        last = List.last(rest)
        middle = Enum.drop(rest, -1)
        first = fit_x_label(first, width)
        last = fit_x_label(last, width)
        first_end = label_end(first)

        {middle, _next_start} =
          middle
          |> Enum.reverse()
          |> Enum.reduce({[], elem(last, 0)}, fn {column, label}, {acc, next_start} ->
            label_width = String.length(label)

            column =
              column
              |> min(max(width - label_width, 0))
              |> min(next_start - @tick_label_gap - label_width)

            if column > first_end + @tick_label_gap do
              {[{column, label} | acc], column}
            else
              {acc, next_start}
            end
          end)

        [first | middle] ++ [last]
    end
  end

  defp fit_x_label({column, label}, width) do
    label = to_string(label)
    label_width = String.length(label)
    {min(column, max(width - label_width, 0)), label}
  end

  defp label_end({column, label}), do: column + String.length(label) - 1

  defp default_axis_ticks(true, [], nil), do: :auto
  defp default_axis_ticks(_present?, _labels, ticks), do: ticks

  defp axis_labels(axis, min, max, auto_size)

  defp axis_labels(%{labels: labels}, min, max, _auto_size)
       when is_list(labels) and labels != [] do
    cond do
      Enum.all?(labels, &positioned_label?/1) ->
        Enum.map(labels, fn {value, label} -> {value, to_string(label)} end)

      length(labels) == 1 ->
        [{min, labels |> hd() |> to_string()}]

      true ->
        labels
        |> Enum.with_index()
        |> Enum.map(fn {label, index} ->
          value = min + index * (max - min) / max(length(labels) - 1, 1)
          {value, to_string(label)}
        end)
    end
  end

  defp axis_labels(%{ticks: ticks} = axis, min, max, auto_size)
       when ticks == :auto or ticks == "auto" do
    tick_labels(axis, min, max, auto_tick_count(auto_size))
  end

  defp axis_labels(%{ticks: ticks} = axis, min, max, _auto_size)
       when is_integer(ticks) and ticks > 0 do
    tick_labels(axis, min, max, ticks)
  end

  defp axis_labels(_axis, _min, _max, _auto_size), do: []

  defp tick_labels(axis, min, max, count) do
    count = max(count, 1)

    0..(count - 1)
    |> Enum.map(fn index ->
      value =
        if count == 1 do
          min
        else
          min + index * (max - min) / (count - 1)
        end

      {value, format_axis_value(axis.format, value)}
    end)
  end

  defp auto_tick_count(nil), do: 3

  defp auto_tick_count({:x, width}) when is_integer(width),
    do: width |> div(16) |> Kernel.+(1) |> clamp(2, 5)

  defp auto_tick_count(height) when is_integer(height) and height <= 1, do: 1

  defp auto_tick_count(height) when is_integer(height),
    do: height |> Kernel.+(2) |> div(3) |> clamp(2, 5)

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end

  defp label_text(nil), do: ""
  defp label_text({_value, label}), do: label

  defp join_label(title, label) do
    title = if empty_text?(title), do: "", else: to_string(title)
    label = if empty_text?(label), do: "", else: label

    case {title, label} do
      {"", ""} -> ""
      {"", label} -> label
      {title, ""} -> title
      {title, label} -> title <> " " <> label
    end
  end

  defp positioned_label?({value, _label}) when is_number(value), do: true
  defp positioned_label?(_label), do: false

  defp format_axis_value(format, value) when is_function(format, 1),
    do: format.(value) |> to_string()

  defp format_axis_value(_format, value) when is_integer(value), do: Integer.to_string(value)

  defp format_axis_value(_format, value) when is_float(value) do
    rounded = Float.round(value, 1)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: :erlang.float_to_binary(rounded, decimals: 1)
  end

  defp empty_text?(nil), do: true
  defp empty_text?(""), do: true
  defp empty_text?(_value), do: false

  defp overlay_center(line, text) do
    start = div(max(String.length(line) - String.length(text), 0), 2)
    overlay_at(line, text, start)
  end

  defp overlay_at(line, text, column) do
    text = to_string(text)
    column = max(column, 0)
    prefix = String.slice(line, 0, column)
    suffix_start = min(column + String.length(text), String.length(line))
    suffix = String.slice(line, suffix_start, String.length(line) - suffix_start)

    (prefix <> text <> suffix)
    |> String.slice(0, String.length(line))
    |> String.pad_trailing(String.length(line))
  end

  defp fit_line(line, width) when is_binary(line) do
    line
    |> String.slice(0, width)
    |> String.pad_trailing(width)
  end

  defp fit_line(line, width) when is_list(line) do
    {fitted, line_width} =
      Enum.reduce_while(line, {[], 0}, fn
        %TextSpan{text: text, style: style}, {acc, used} ->
          append_fitted_span(acc, used, text, style, width)

        text, {acc, used} when is_binary(text) ->
          append_fitted_span(acc, used, text, %{}, width)
      end)

    fitted = Enum.reverse(fitted)

    if line_width < width do
      fitted ++ [TextSpan.new(String.duplicate(" ", width - line_width))]
    else
      fitted
    end
  end

  defp append_fitted_span(acc, used, text, style, width) do
    remaining = width - used

    cond do
      remaining <= 0 ->
        {:halt, {acc, used}}

      String.length(text) <= remaining ->
        {:cont, {[TextSpan.new(text, style) | acc], used + String.length(text)}}

      true ->
        sliced = String.slice(text, 0, remaining)
        {:halt, {[TextSpan.new(sliced, style) | acc], width}}
    end
  end
end
