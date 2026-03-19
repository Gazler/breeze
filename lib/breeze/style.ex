defmodule Breeze.Style do
  @moduledoc false

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

        apply_style(style, acc)
      end)

    {bb_style, attributes} =
      merge_style_map(normalize_style_map(style_state.style), {bb_style, attributes})

    struct(Breeze.Element, %{style: Map.from_struct(bb_style), attributes: attributes})
  end

  defp apply_style("border", {style, attrs}), do: {BackBreeze.Style.border(style), attrs}
  defp apply_style("bold", {style, attrs}), do: {BackBreeze.Style.bold(style), attrs}
  defp apply_style("italic", {style, attrs}), do: {BackBreeze.Style.italic(style), attrs}
  defp apply_style("inverse", {style, attrs}), do: {BackBreeze.Style.reverse(style), attrs}
  defp apply_style("reverse", {style, attrs}), do: {BackBreeze.Style.reverse(style), attrs}
  defp apply_style("inline", {style, attrs}), do: {style, Map.put(attrs, :display, :inline)}

  defp apply_style("grid", {style, attrs}) do
    display =
      case Map.get(attrs, :display) do
        %BackBreeze.Grid{} = grid -> grid
        _ -> %BackBreeze.Grid{columns: 1}
      end

    {style, Map.put(attrs, :display, display)}
  end

  defp apply_style("grid-cols-" <> num, {style, attrs}) do
    display =
      case Map.get(attrs, :display) do
        %BackBreeze.Grid{} = grid -> grid
        _ -> %BackBreeze.Grid{}
      end

    {style, Map.put(attrs, :display, %{display | columns: String.to_integer(num)})}
  end

  defp apply_style("grid-rows-" <> num, {style, attrs}) do
    display =
      case Map.get(attrs, :display) do
        %BackBreeze.Grid{} = grid -> grid
        _ -> %BackBreeze.Grid{}
      end

    {style, Map.put(attrs, :display, %{display | rows: String.to_integer(num)})}
  end

  defp apply_style("layer-" <> num, {style, attrs}) do
    {style, Map.put(attrs, :layer, String.to_integer(num))}
  end

  defp apply_style("overflow-scroll", {style, attrs}),
    do: {BackBreeze.Style.overflow(style, :scroll), attrs}

  defp apply_style("overflow-" <> overflow, {style, attrs}),
    do: {BackBreeze.Style.overflow(style, String.to_existing_atom(overflow)), attrs}

  defp apply_style("offset-top-" <> num, {style, attrs}) do
    {_, left} = Map.get(attrs, :scroll, {0, 0})
    {style, Map.put(attrs, :scroll, {String.to_integer(num), left})}
  end

  defp apply_style("offset-left-" <> num, {style, attrs}) do
    {top, _} = Map.get(attrs, :scroll, {0, 0})
    {style, Map.put(attrs, :scroll, {top, String.to_integer(num)})}
  end

  defp apply_style("absolute", {style, attrs}), do: {style, Map.put(attrs, :position, :absolute)}
  defp apply_style("fixed", {style, attrs}), do: {style, Map.put(attrs, :position, :fixed)}

  defp apply_style("center", {style, attrs}) do
    {style, attrs |> Map.put(:left, :center) |> Map.put(:top, :center)}
  end

  defp apply_style("center-x", {style, attrs}) do
    {style, Map.put(attrs, :left, :center)}
  end

  defp apply_style("center-y", {style, attrs}) do
    {style, Map.put(attrs, :top, :center)}
  end

  defp apply_style("inset-x-" <> num, {style, attrs}) do
    inset = String.to_integer(num)
    {style, attrs |> Map.put(:left, inset) |> Map.put(:right, inset)}
  end

  defp apply_style("inset-y-" <> num, {style, attrs}) do
    inset = String.to_integer(num)
    {style, attrs |> Map.put(:top, inset) |> Map.put(:bottom, inset)}
  end

  defp apply_style("inset-" <> num, {style, attrs}) do
    inset = String.to_integer(num)

    {style,
     attrs
     |> Map.put(:left, inset)
     |> Map.put(:right, inset)
     |> Map.put(:top, inset)
     |> Map.put(:bottom, inset)}
  end

  defp apply_style("left-" <> num, {style, attrs}),
    do: {style, Map.put(attrs, :left, String.to_integer(num))}

  defp apply_style("right-" <> num, {style, attrs}),
    do: {style, Map.put(attrs, :right, String.to_integer(num))}

  defp apply_style("top-" <> num, {style, attrs}),
    do: {style, Map.put(attrs, :top, String.to_integer(num))}

  defp apply_style("bottom-" <> num, {style, attrs}),
    do: {style, Map.put(attrs, :bottom, String.to_integer(num))}

  defp apply_style("width-auto", {style, attrs}),
    do: {BackBreeze.Style.width(style, :auto), attrs}

  defp apply_style("width-full", {style, attrs}),
    do: {BackBreeze.Style.width(style, :full), attrs}

  defp apply_style("width-screen", {style, attrs}),
    do: {BackBreeze.Style.width(style, :screen), attrs}

  defp apply_style("width-" <> num, {style, attrs}),
    do: {BackBreeze.Style.width(style, String.to_integer(num)), attrs}

  defp apply_style("height-auto", {style, attrs}),
    do: {BackBreeze.Style.height(style, :auto), attrs}

  defp apply_style("height-screen", {style, attrs}),
    do: {BackBreeze.Style.height(style, :screen), attrs}

  defp apply_style("height-full", {style, attrs}),
    do: {BackBreeze.Style.height(style, :full), attrs}

  defp apply_style("height-" <> num, {style, attrs}),
    do: {BackBreeze.Style.height(style, String.to_integer(num)), attrs}

  defp apply_style("padding-top-" <> num, {style, attrs}),
    do: {BackBreeze.Style.padding_top(style, String.to_integer(num)), attrs}

  defp apply_style("padding-right-" <> num, {style, attrs}),
    do: {BackBreeze.Style.padding_right(style, String.to_integer(num)), attrs}

  defp apply_style("padding-bottom-" <> num, {style, attrs}),
    do: {BackBreeze.Style.padding_bottom(style, String.to_integer(num)), attrs}

  defp apply_style("padding-left-" <> num, {style, attrs}),
    do: {BackBreeze.Style.padding_left(style, String.to_integer(num)), attrs}

  defp apply_style("padding-" <> num, {style, attrs}),
    do: {BackBreeze.Style.padding(style, String.to_integer(num)), attrs}

  defp apply_style("text-left", {style, attrs}),
    do: {BackBreeze.Style.text_align(style, :left), attrs}

  defp apply_style("text-center", {style, attrs}),
    do: {BackBreeze.Style.text_align(style, :center), attrs}

  defp apply_style("text-right", {style, attrs}),
    do: {BackBreeze.Style.text_align(style, :right), attrs}

  defp apply_style("text-" <> num, {style, attrs}),
    do: {BackBreeze.Style.foreground_color(style, String.to_integer(num)), attrs}

  defp apply_style("bg-" <> num, {style, attrs}),
    do: {BackBreeze.Style.background_color(style, String.to_integer(num)), attrs}

  defp apply_style("scrollbar-none", {style, attrs}),
    do: {BackBreeze.Style.scrollbar(style, false), attrs}

  defp apply_style("scrollbar-arrows", {style, attrs}),
    do: {BackBreeze.Style.scrollbar(style, %{arrows: true}), attrs}

  defp apply_style("border-rounded", {style, attrs}),
    do: {BackBreeze.Style.border(style, :rounded), attrs}

  defp apply_style("border-" <> num, {style, attrs}),
    do: {BackBreeze.Style.border_color(style, String.to_integer(num)), attrs}

  defp apply_style(_, acc), do: acc

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
      {key, value} -> [Enum.join(class_segments(key) ++ class_segments(value), "-")]
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

  defp merge_style_map(style_map, acc) when map_size(style_map) == 0, do: acc

  defp merge_style_map(style_map, {style, attrs}) do
    Enum.reduce(style_map, {style, attrs}, fn {key, value}, {acc_style, acc_attrs} ->
      merge_style_entry(normalize_style_key(key), value, {acc_style, acc_attrs})
    end)
  end

  defp merge_style_entry(:display, value, {style, attrs}),
    do: {style, Map.put(attrs, :display, value)}

  defp merge_style_entry(:position, value, {style, attrs}),
    do: {style, Map.put(attrs, :position, value)}

  defp merge_style_entry(:left, value, {style, attrs}), do: {style, Map.put(attrs, :left, value)}

  defp merge_style_entry(:right, value, {style, attrs}),
    do: {style, Map.put(attrs, :right, value)}

  defp merge_style_entry(:top, value, {style, attrs}), do: {style, Map.put(attrs, :top, value)}

  defp merge_style_entry(:bottom, value, {style, attrs}),
    do: {style, Map.put(attrs, :bottom, value)}

  defp merge_style_entry(:layer, value, {style, attrs}),
    do: {style, Map.put(attrs, :layer, value)}

  defp merge_style_entry(:scroll, value, {style, attrs}),
    do: {style, Map.put(attrs, :scroll, value)}

  defp merge_style_entry(:border, value, {style, attrs}),
    do: {%{style | border: normalize_border(value)}, attrs}

  defp merge_style_entry(:bold, value, {style, attrs}),
    do: {%{style | bold: truthy?(value)}, attrs}

  defp merge_style_entry(:italic, value, {style, attrs}),
    do: {%{style | italic: truthy?(value)}, attrs}

  defp merge_style_entry(:reverse, value, {style, attrs}),
    do: {%{style | reverse: truthy?(value)}, attrs}

  defp merge_style_entry(:text_align, value, {style, attrs}),
    do: {%{style | text_align: value}, attrs}

  defp merge_style_entry(:padding, value, {style, attrs}), do: {%{style | padding: value}, attrs}

  defp merge_style_entry(:padding_top, value, {style, attrs}),
    do: {%{style | padding_top: value}, attrs}

  defp merge_style_entry(:padding_right, value, {style, attrs}),
    do: {%{style | padding_right: value}, attrs}

  defp merge_style_entry(:padding_bottom, value, {style, attrs}),
    do: {%{style | padding_bottom: value}, attrs}

  defp merge_style_entry(:padding_left, value, {style, attrs}),
    do: {%{style | padding_left: value}, attrs}

  defp merge_style_entry(:width, value, {style, attrs}), do: {%{style | width: value}, attrs}
  defp merge_style_entry(:height, value, {style, attrs}), do: {%{style | height: value}, attrs}

  defp merge_style_entry(:overflow, value, {style, attrs}),
    do: {%{style | overflow: value}, attrs}

  defp merge_style_entry(:scrollbar, value, {style, attrs}),
    do: {%{style | scrollbar: value}, attrs}

  defp merge_style_entry(:foreground_color, value, {style, attrs}),
    do: {%{style | foreground_color: value}, attrs}

  defp merge_style_entry(:background_color, value, {style, attrs}),
    do: {%{style | background_color: value}, attrs}

  defp merge_style_entry(:border_color, value, {style, attrs}),
    do: {%{style | border_color: value}, attrs}

  defp merge_style_entry(:text, value, {style, attrs}),
    do: {%{style | foreground_color: value}, attrs}

  defp merge_style_entry(:bg, value, {style, attrs}),
    do: {%{style | background_color: value}, attrs}

  defp merge_style_entry(:color, value, {style, attrs}),
    do: {%{style | foreground_color: value}, attrs}

  defp merge_style_entry(_key, _value, acc), do: acc

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
end
