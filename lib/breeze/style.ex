defmodule Breeze.Style do
  @moduledoc false

  alias Breeze.Theme

  @type state :: %{class: list(), style: list()}

  @spec empty() :: state()
  def empty, do: %{class: [], style: []}

  @spec put_class(state(), term()) :: state()
  def put_class(style_state, value) do
    update_in(style_state.class, &[value | &1])
  end

  @spec put_style(state(), term()) :: state()
  def put_style(style_state, value) when is_binary(value), do: put_class(style_state, value)
  def put_style(style_state, nil), do: style_state
  def put_style(style_state, false), do: style_state
  def put_style(style_state, value), do: update_in(style_state.style, &[value | &1])

  @spec merge_modifiers(state(), list()) :: state()
  def merge_modifiers(style_state, modifiers) do
    Enum.reduce(modifiers, style_state, &put_style(&2, &1))
  end

  @spec to_element(state(), keyword()) :: Breeze.Element.t()
  def to_element(style_state, opts) do
    theme = Theme.new(Keyword.get(opts, :theme), terminal: Keyword.get(opts, :terminal))

    class_input =
      case Keyword.get_values(opts, :style) do
        [] -> style_state.class
        other -> [style_state.class | other]
      end

    {bb_style, attributes} =
      class_input
      |> normalize_class_input()
      |> String.split(" ", trim: true)
      |> Enum.map(&String.split(&1, ":"))
      |> Enum.sort_by(&length/1)
      |> Enum.reduce({%BackBreeze.Style{}, %{}}, fn style, acc ->
        style =
          Enum.reduce_while(style, nil, fn
            "focus", _ ->
              if Keyword.get(opts, :focus), do: {:cont, nil}, else: {:halt, nil}

            "selected", _ ->
              if Keyword.get(opts, :selected), do: {:cont, nil}, else: {:halt, nil}

            other, _ ->
              {:halt, other}
          end)

        apply_style(style, acc, theme)
      end)

    {bb_style, attributes} =
      merge_style_map(normalize_style_map(style_state.style), {bb_style, attributes}, theme)

    bb_style =
      if Keyword.get(opts, :apply_theme_defaults, false) do
        apply_theme_defaults(bb_style, theme)
      else
        bb_style
      end

    struct(Breeze.Element, %{style: Map.from_struct(bb_style), attributes: attributes})
  end

  defp apply_style("border", {style, attrs}, _theme), do: {BackBreeze.Style.border(style), attrs}
  defp apply_style("bold", {style, attrs}, _theme), do: {BackBreeze.Style.bold(style), attrs}
  defp apply_style("italic", {style, attrs}, _theme), do: {BackBreeze.Style.italic(style), attrs}

  defp apply_style("inverse", {style, attrs}, _theme),
    do: {BackBreeze.Style.reverse(style), attrs}

  defp apply_style("reverse", {style, attrs}, _theme),
    do: {BackBreeze.Style.reverse(style), attrs}

  defp apply_style("inline", {style, attrs}, _theme),
    do: {style, Map.put(attrs, :display, :inline)}

  defp apply_style("grid", {style, attrs}, _theme) do
    display =
      case Map.get(attrs, :display) do
        %BackBreeze.Grid{} = grid -> grid
        _ -> %BackBreeze.Grid{columns: 1}
      end

    {style, Map.put(attrs, :display, display)}
  end

  defp apply_style("grid-cols-" <> num, {style, attrs}, _theme) do
    display =
      case Map.get(attrs, :display) do
        %BackBreeze.Grid{} = grid -> grid
        _ -> %BackBreeze.Grid{}
      end

    {style, Map.put(attrs, :display, %{display | columns: String.to_integer(num)})}
  end

  defp apply_style("grid-rows-" <> num, {style, attrs}, _theme) do
    display =
      case Map.get(attrs, :display) do
        %BackBreeze.Grid{} = grid -> grid
        _ -> %BackBreeze.Grid{}
      end

    {style, Map.put(attrs, :display, %{display | rows: String.to_integer(num)})}
  end

  defp apply_style("layer-" <> num, {style, attrs}, _theme) do
    {style, Map.put(attrs, :layer, String.to_integer(num))}
  end

  defp apply_style("overflow-scroll", {style, attrs}, _theme),
    do: {BackBreeze.Style.overflow(style, :scroll), attrs}

  defp apply_style("overflow-" <> overflow, {style, attrs}, _theme),
    do: {BackBreeze.Style.overflow(style, String.to_existing_atom(overflow)), attrs}

  defp apply_style("offset-top-" <> num, {style, attrs}, _theme) do
    {_, left} = Map.get(attrs, :scroll, {0, 0})
    {style, Map.put(attrs, :scroll, {String.to_integer(num), left})}
  end

  defp apply_style("offset-left-" <> num, {style, attrs}, _theme) do
    {top, _} = Map.get(attrs, :scroll, {0, 0})
    {style, Map.put(attrs, :scroll, {top, String.to_integer(num)})}
  end

  defp apply_style("absolute", {style, attrs}, _theme),
    do: {style, Map.put(attrs, :position, :absolute)}

  defp apply_style("fixed", {style, attrs}, _theme),
    do: {style, Map.put(attrs, :position, :fixed)}

  defp apply_style("center", {style, attrs}, _theme) do
    {style, attrs |> Map.put(:left, :center) |> Map.put(:top, :center)}
  end

  defp apply_style("center-x", {style, attrs}, _theme) do
    {style, Map.put(attrs, :left, :center)}
  end

  defp apply_style("center-y", {style, attrs}, _theme) do
    {style, Map.put(attrs, :top, :center)}
  end

  defp apply_style("inset-x-" <> num, {style, attrs}, _theme) do
    inset = String.to_integer(num)
    {style, attrs |> Map.put(:left, inset) |> Map.put(:right, inset)}
  end

  defp apply_style("inset-y-" <> num, {style, attrs}, _theme) do
    inset = String.to_integer(num)
    {style, attrs |> Map.put(:top, inset) |> Map.put(:bottom, inset)}
  end

  defp apply_style("inset-" <> num, {style, attrs}, _theme) do
    inset = String.to_integer(num)

    {style,
     attrs
     |> Map.put(:left, inset)
     |> Map.put(:right, inset)
     |> Map.put(:top, inset)
     |> Map.put(:bottom, inset)}
  end

  defp apply_style("left-" <> num, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :left, String.to_integer(num))}

  defp apply_style("right-" <> num, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :right, String.to_integer(num))}

  defp apply_style("top-" <> num, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :top, String.to_integer(num))}

  defp apply_style("bottom-" <> num, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :bottom, String.to_integer(num))}

  defp apply_style("width-auto", {style, attrs}, _theme),
    do: {BackBreeze.Style.width(style, :auto), attrs}

  defp apply_style("width-full", {style, attrs}, _theme),
    do: {BackBreeze.Style.width(style, :full), attrs}

  defp apply_style("width-screen", {style, attrs}, _theme),
    do: {BackBreeze.Style.width(style, :screen), attrs}

  defp apply_style("width-" <> num, {style, attrs}, _theme),
    do: {BackBreeze.Style.width(style, String.to_integer(num)), attrs}

  defp apply_style("height-auto", {style, attrs}, _theme),
    do: {BackBreeze.Style.height(style, :auto), attrs}

  defp apply_style("height-screen", {style, attrs}, _theme),
    do: {BackBreeze.Style.height(style, :screen), attrs}

  defp apply_style("height-full", {style, attrs}, _theme),
    do: {BackBreeze.Style.height(style, :full), attrs}

  defp apply_style("height-" <> num, {style, attrs}, _theme),
    do: {BackBreeze.Style.height(style, String.to_integer(num)), attrs}

  defp apply_style("padding-top-" <> num, {style, attrs}, _theme),
    do: {BackBreeze.Style.padding_top(style, String.to_integer(num)), attrs}

  defp apply_style("padding-right-" <> num, {style, attrs}, _theme),
    do: {BackBreeze.Style.padding_right(style, String.to_integer(num)), attrs}

  defp apply_style("padding-bottom-" <> num, {style, attrs}, _theme),
    do: {BackBreeze.Style.padding_bottom(style, String.to_integer(num)), attrs}

  defp apply_style("padding-left-" <> num, {style, attrs}, _theme),
    do: {BackBreeze.Style.padding_left(style, String.to_integer(num)), attrs}

  defp apply_style("padding-" <> num, {style, attrs}, _theme),
    do: {BackBreeze.Style.padding(style, String.to_integer(num)), attrs}

  defp apply_style("text-left", {style, attrs}, _theme),
    do: {BackBreeze.Style.text_align(style, :left), attrs}

  defp apply_style("text-center", {style, attrs}, _theme),
    do: {BackBreeze.Style.text_align(style, :center), attrs}

  defp apply_style("text-right", {style, attrs}, _theme),
    do: {BackBreeze.Style.text_align(style, :right), attrs}

  defp apply_style("text", {style, attrs}, theme),
    do: {BackBreeze.Style.foreground_color(style, Theme.resolve_color(theme, :text)), attrs}

  defp apply_style("text-" <> color, {style, attrs}, theme),
    do: {BackBreeze.Style.foreground_color(style, Theme.resolve_color(theme, color)), attrs}

  defp apply_style("bg", {style, attrs}, theme),
    do: {BackBreeze.Style.background_color(style, Theme.resolve_color(theme, :background)), attrs}

  defp apply_style("bg-" <> color, {style, attrs}, theme),
    do: {BackBreeze.Style.background_color(style, Theme.resolve_color(theme, color)), attrs}

  defp apply_style("scrollbar-none", {style, attrs}, _theme),
    do: {BackBreeze.Style.scrollbar(style, false), attrs}

  defp apply_style("scrollbar-arrows", {style, attrs}, _theme),
    do: {BackBreeze.Style.scrollbar(style, %{arrows: true}), attrs}

  defp apply_style("border-rounded", {style, attrs}, _theme),
    do: {BackBreeze.Style.border(style, :rounded), attrs}

  defp apply_style("border-" <> color, {style, attrs}, theme),
    do: {BackBreeze.Style.border_color(style, Theme.resolve_color(theme, color)), attrs}

  defp apply_style(_, acc, _theme), do: acc

  defp normalize_class_input(value) when is_list(value) do
    if Keyword.keyword?(value) do
      normalize_class_input(Map.new(value))
    else
      value
      |> Enum.reverse()
      |> Enum.flat_map(&class_segments/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")
    end
  end

  defp normalize_class_input(value) do
    value
    |> class_segments()
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp class_segments(nil), do: []
  defp class_segments(false), do: []
  defp class_segments(value) when is_binary(value), do: [String.trim(value)]
  defp class_segments(value) when is_atom(value), do: [Atom.to_string(value)]

  defp class_segments(value) when is_list(value) do
    Enum.flat_map(value, &class_segments/1)
  end

  defp class_segments(value) when is_map(value) do
    value
    |> Enum.flat_map(fn
      {key, true} -> class_segments(key)
      {_key, truthy} when truthy in [false, nil] -> []
      {key, nested_value} -> [Enum.join(class_segments(key) ++ class_segments(nested_value), "-")]
    end)
  end

  defp class_segments(value), do: [to_string(value)]

  defp normalize_style_map(values) when is_list(values) do
    if Keyword.keyword?(values) do
      Map.new(values)
    else
      values
      |> Enum.reverse()
      |> Enum.reduce(%{}, fn value, acc -> Map.merge(acc, coerce_style_map(value)) end)
    end
  end

  defp normalize_style_map(value), do: coerce_style_map(value)

  defp coerce_style_map(nil), do: %{}
  defp coerce_style_map(false), do: %{}
  defp coerce_style_map(%BackBreeze.Style{} = style), do: Map.from_struct(style)
  defp coerce_style_map(%_{} = struct), do: Map.from_struct(struct)
  defp coerce_style_map(value) when is_map(value), do: value

  defp coerce_style_map(value) when is_list(value) do
    if Keyword.keyword?(value), do: Map.new(value), else: %{}
  end

  defp coerce_style_map(_value), do: %{}

  defp merge_style_map(style_map, acc, _theme) when map_size(style_map) == 0, do: acc

  defp merge_style_map(style_map, {style, attrs}, theme) do
    Enum.reduce(style_map, {style, attrs}, fn {key, value}, {acc_style, acc_attrs} ->
      merge_style_entry(normalize_style_key(key), value, {acc_style, acc_attrs}, theme)
    end)
  end

  defp merge_style_entry(:display, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :display, value)}

  defp merge_style_entry(:position, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :position, value)}

  defp merge_style_entry(:left, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :left, value)}

  defp merge_style_entry(:right, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :right, value)}

  defp merge_style_entry(:top, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :top, value)}

  defp merge_style_entry(:bottom, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :bottom, value)}

  defp merge_style_entry(:layer, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :layer, value)}

  defp merge_style_entry(:scroll, value, {style, attrs}, _theme),
    do: {style, Map.put(attrs, :scroll, value)}

  defp merge_style_entry(:border, value, {style, attrs}, _theme),
    do: {%{style | border: normalize_border(value)}, attrs}

  defp merge_style_entry(:bold, value, {style, attrs}, _theme),
    do: {%{style | bold: truthy?(value)}, attrs}

  defp merge_style_entry(:italic, value, {style, attrs}, _theme),
    do: {%{style | italic: truthy?(value)}, attrs}

  defp merge_style_entry(:reverse, value, {style, attrs}, _theme),
    do: {%{style | reverse: truthy?(value)}, attrs}

  defp merge_style_entry(:text_align, value, {style, attrs}, _theme),
    do: {%{style | text_align: value}, attrs}

  defp merge_style_entry(:padding, value, {style, attrs}, _theme),
    do: {%{style | padding: value}, attrs}

  defp merge_style_entry(:padding_top, value, {style, attrs}, _theme),
    do: {%{style | padding_top: value}, attrs}

  defp merge_style_entry(:padding_right, value, {style, attrs}, _theme),
    do: {%{style | padding_right: value}, attrs}

  defp merge_style_entry(:padding_bottom, value, {style, attrs}, _theme),
    do: {%{style | padding_bottom: value}, attrs}

  defp merge_style_entry(:padding_left, value, {style, attrs}, _theme),
    do: {%{style | padding_left: value}, attrs}

  defp merge_style_entry(:width, value, {style, attrs}, _theme),
    do: {%{style | width: value}, attrs}

  defp merge_style_entry(:height, value, {style, attrs}, _theme),
    do: {%{style | height: value}, attrs}

  defp merge_style_entry(:overflow, value, {style, attrs}, _theme),
    do: {%{style | overflow: value}, attrs}

  defp merge_style_entry(:scrollbar, value, {style, attrs}, _theme),
    do: {%{style | scrollbar: value}, attrs}

  defp merge_style_entry(:foreground_color, value, {style, attrs}, theme),
    do: {%{style | foreground_color: Theme.resolve_color(theme, value)}, attrs}

  defp merge_style_entry(:background_color, value, {style, attrs}, theme),
    do: {%{style | background_color: Theme.resolve_color(theme, value)}, attrs}

  defp merge_style_entry(:border_color, value, {style, attrs}, theme),
    do: {%{style | border_color: Theme.resolve_color(theme, value)}, attrs}

  defp merge_style_entry(:text, value, {style, attrs}, theme),
    do: {%{style | foreground_color: Theme.resolve_color(theme, value)}, attrs}

  defp merge_style_entry(:bg, value, {style, attrs}, theme),
    do: {%{style | background_color: Theme.resolve_color(theme, value)}, attrs}

  defp merge_style_entry(:color, value, {style, attrs}, theme),
    do: {%{style | foreground_color: Theme.resolve_color(theme, value)}, attrs}

  defp merge_style_entry(_key, _value, acc, _theme), do: acc

  defp normalize_style_key(key) when is_atom(key), do: key

  defp normalize_style_key(key) when is_binary(key) do
    key
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp normalize_style_key(key), do: key |> to_string() |> normalize_style_key()

  defp normalize_border(:line), do: BackBreeze.Border.line()
  defp normalize_border(:rounded), do: BackBreeze.Border.rounded()
  defp normalize_border(value), do: value

  defp truthy?(value), do: value not in [false, nil]

  defp apply_theme_defaults(style, theme) do
    defaults = Theme.default_style(theme)

    style
    |> maybe_put_default_foreground(defaults)
    |> maybe_put_default_background(defaults)
    |> maybe_put_default_border_color(defaults)
  end

  defp maybe_put_default_foreground(%{foreground_color: nil} = style, defaults) do
    %{style | foreground_color: Map.get(defaults, :foreground_color)}
  end

  defp maybe_put_default_foreground(style, _defaults), do: style

  defp maybe_put_default_background(%{background_color: nil, border: border} = style, defaults) do
    if border == BackBreeze.Border.none() do
      style
    else
      %{style | background_color: Map.get(defaults, :background_color)}
    end
  end

  defp maybe_put_default_background(style, _defaults), do: style

  defp maybe_put_default_border_color(%{border_color: nil, border: border} = style, defaults) do
    if border == BackBreeze.Border.none() do
      style
    else
      %{style | border_color: Map.get(defaults, :border_color)}
    end
  end

  defp maybe_put_default_border_color(style, _defaults), do: style
end
