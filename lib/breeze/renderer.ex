defmodule Breeze.Renderer do
  @moduledoc false

  alias BackBreeze.Box
  alias BackBreeze.Style

  def render_to_string(mod, assigns, opts \\ []) do
    {_, %{content: content}} = render(mod, assigns, opts)
    content
  end

  def render(mod, assigns, opts \\ []) do
    [{_tag, _, root_children}] =
      mod.render(assigns)
      |> Breeze.Template.render_to_tree(assigns)

    {acc, box} = build_from_tree_nodes(root_children, opts)

    %{box: box, dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(box)

    {Map.put(acc, :dimensions, dimensions), box}
  end

  defp build_from_tree_nodes(children, opts) do
    {acc, box} =
      build_tree(
        children,
        %BackBreeze.Box{},
        [],
        "",
        [],
        %{focusables: [], id: 0, elements: %{}, ids: [], flags: []},
        opts
      )

    acc = %{acc | elements: Map.put(acc.elements, acc.id, acc.flags)}
    ids = Enum.reverse(acc.ids)
    focusables = Enum.reverse(acc.focusables) |> then(&Enum.filter(ids, fn id -> id in &1 end))
    {%{acc | ids: ids, focusables: focusables}, box}
  end

  defp build_tree(
         [{:attribute, ["style", style]} | rest],
         box,
         children,
         _style,
         flags,
         acc,
         opts
       ) do
    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([{:attribute, ["id", box_id]} | rest], box, children, style, flags, acc, opts) do
    ids = [box_id | acc.ids]
    acc = %{acc | ids: ids, flags: Keyword.put(acc.flags, :id, box_id)}
    build_tree(rest, box, children, style, Keyword.put(flags, :id, box_id), acc, opts)
  end

  defp build_tree(
         [{:attribute, ["implicit", mod]} | rest],
         box,
         children,
         style,
         flags,
         acc,
         opts
       ) do
    mod = String.to_atom(mod)
    acc = %{acc | flags: Keyword.put(acc.flags, :implicit, mod)}
    build_tree(rest, box, children, style, Keyword.put(flags, :implicit, mod), acc, opts)
  end

  defp build_tree([{:attribute, [flag, value]} | rest], box, children, style, flags, acc, opts) do
    flag = String.to_atom(flag)
    acc = %{acc | flags: Keyword.put(acc.flags, flag, value)}
    build_tree(rest, box, children, style, Keyword.put(flags, flag, value), acc, opts)
  end

  defp build_tree([{:attribute_bool, [attr]} | rest], box, children, style, flags, acc, opts) do
    {flags, acc} =
      case attr do
        "focusable" ->
          {Keyword.put(flags, :focusable, true),
           %{acc | flags: Keyword.put(acc.flags, :focusable, true)}}

        _ ->
          {flags, acc}
      end

    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([content | rest], box, children, style, flags, acc, opts)
       when is_binary(content) do
    box = %{box | content: String.trim_trailing(content, "\n  ")}
    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([{:live, attrs} | rest], box, children, style, flags, acc, opts) do
    {acc, child} =
      case Keyword.get(opts, :live_view) do
        fun when is_function(fun, 2) ->
          case fun.(attrs, opts) do
            {:rendered, prefix, child_acc, child_box} ->
              {merge_live_acc(acc, namespace_live_acc(child_acc, prefix)), child_box}

            :preloaded ->
              {acc, nil}

            _ ->
              {acc, nil}
          end

        _ ->
          {acc, nil}
      end

    children = if child, do: [child | children], else: children
    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([{:box, _, nodes} | rest], box, children, style, flags, acc, opts) do
    child_flags =
      cond do
        Keyword.get(flags, :implicit) -> [implicit_owner: Keyword.fetch!(flags, :id)]
        implicit_owner = Keyword.get(flags, :implicit_owner) -> [implicit_owner: implicit_owner]
        true -> []
      end

    acc = %{
      acc
      | flags: child_flags,
        id: acc.id + 1,
        elements: Map.put(acc.elements, acc.id, acc.flags)
    }

    {acc, child} = build_tree(nodes, %BackBreeze.Box{}, [], "", child_flags, acc, opts)
    build_tree(rest, box, [child | children], style, flags, acc, opts)
  end

  defp build_tree([], box, children, style, flags, acc, opts) do
    %{focusables: focusables} = acc

    focused =
      (Keyword.get(flags, :id) || Keyword.get(flags, :implicit_owner)) ==
        Keyword.get(opts, :focused)

    flags = if focused, do: Keyword.put(flags, :focused, focused), else: flags

    style_flags =
      if focused do
        [focus: true]
      else
        []
      end

    implicit_state = Keyword.get(opts, :implicit_state, %{})
    implicit_owner = Keyword.get(flags, :implicit_owner)
    root_id = Keyword.get(flags, :id)

    id =
      cond do
        Keyword.get(flags, :implicit) && root_id -> root_id
        implicit_owner -> implicit_owner
        true -> root_id
      end

    {implicit_mod, implicit} =
      case id && get_in(implicit_state, [id]) do
        nil -> {nil, nil}
        {mod, state} -> {mod, state}
      end

    type = if id == root_id, do: :root, else: :child

    {style_flags, style_modifiers, scroll_modifier} =
      if implicit do
        modifiers = implicit_mod.handle_modifiers(type, flags, implicit)
        parse_modifiers(modifiers, style_flags)
      else
        {style_flags, [], %{top: nil, left: nil}}
      end

    focusables =
      if Keyword.get(flags, :focusable),
        do: [Keyword.get(flags, :id) | focusables],
        else: focusables

    element = string_to_styles(append_style_modifiers(style, style_modifiers), style_flags)

    opts =
      element.attributes
      |> merge_scroll_modifier(scroll_modifier)
      |> Map.put(:style, element.style)

    children = Enum.reverse(children)
    content = box.content
    acc = %{acc | focusables: focusables}
    {acc, %{Box.new(opts) | children: children, content: content}}
  end

  defp parse_modifiers(modifiers, style_flags) when is_list(modifiers) do
    {style_flags, style_modifiers, scroll_modifier} =
      Enum.reduce(modifiers, {style_flags, [], %{top: nil, left: nil}}, fn
        {:style, value}, {flags, styles, scroll} when is_binary(value) ->
          {flags, [value | styles], scroll}

        {:scroll_y, top}, {flags, styles, scroll} when is_integer(top) ->
          {flags, styles, %{scroll | top: top}}

        {:scroll_x, left}, {flags, styles, scroll} when is_integer(left) ->
          {flags, styles, %{scroll | left: left}}

        {:scroll, {top, left}}, {flags, styles, _scroll}
        when is_integer(top) and is_integer(left) ->
          {flags, styles, %{top: top, left: left}}

        {flag, value}, {flags, styles, scroll} when is_atom(flag) ->
          {Keyword.put(flags, flag, value), styles, scroll}

        _, acc ->
          acc
      end)

    {style_flags, Enum.reverse(style_modifiers), scroll_modifier}
  end

  defp parse_modifiers(_modifiers, style_flags),
    do: {style_flags, [], %{top: nil, left: nil}}

  defp append_style_modifiers(style, []), do: style

  defp append_style_modifiers(style, modifiers) do
    [style | modifiers]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp merge_scroll_modifier(attributes, %{top: nil, left: nil}), do: attributes

  defp merge_scroll_modifier(attributes, %{top: top, left: left}) do
    {existing_top, existing_left} = Map.get(attributes, :scroll, {0, 0})

    top = if is_integer(top), do: max(top, 0), else: existing_top
    left = if is_integer(left), do: max(left, 0), else: existing_left

    Map.put(attributes, :scroll, {top, left})
  end

  defp merge_live_acc(acc, child_acc) do
    child_offset = acc.id + 1
    child_last_id = max_key(child_acc.elements)

    elements =
      Enum.reduce(child_acc.elements, acc.elements, fn {id, flags}, elements ->
        Map.put(elements, child_offset + id, flags)
      end)

    %{
      acc
      | id: child_offset + child_last_id,
        elements: elements,
        ids: Enum.reverse(child_acc.ids) ++ acc.ids,
        focusables: Enum.reverse(child_acc.focusables) ++ acc.focusables
    }
  end

  defp namespace_live_acc(acc, prefix) do
    %{
      acc
      | ids: Enum.map(acc.ids, &namespace_id(&1, prefix)),
        focusables: Enum.map(acc.focusables, &namespace_id(&1, prefix)),
        elements:
          Map.new(acc.elements, fn {idx, flags} ->
            {idx,
             flags
             |> Keyword.update(:id, nil, &namespace_id(&1, prefix))
             |> Keyword.update(:implicit_owner, nil, &namespace_id(&1, prefix))}
          end)
    }
  end

  defp namespace_id(nil, _prefix), do: nil
  defp namespace_id(id, prefix), do: prefix <> "::" <> id

  defp max_key(elements) do
    elements
    |> Map.keys()
    |> Enum.max(fn -> 0 end)
  end

  defp string_to_styles(str, opts) do
    str =
      case Keyword.get_values(opts, :style) do
        [] -> str
        other -> str <> " " <> Enum.join(other, " ")
      end

    {bb_style, attributes} =
      String.split(str, " ")
      |> Enum.map(&String.split(&1, ":"))
      |> Enum.sort_by(&length/1)
      |> Enum.reduce({%Style{}, %{}}, fn style, acc ->
        style =
          Enum.reduce_while(style, nil, fn
            "focus", _ -> if Keyword.get(opts, :focus), do: {:cont, nil}, else: {:halt, nil}
            "selected", _ -> if Keyword.get(opts, :selected), do: {:cont, nil}, else: {:halt, nil}
            other, _ -> {:halt, other}
          end)

        apply_style(style, acc)
      end)

    struct(Breeze.Element, %{style: Map.from_struct(bb_style), attributes: attributes})
  end

  defp apply_style("border", {style, attrs}), do: {Style.border(style), attrs}
  defp apply_style("bold", {style, attrs}), do: {Style.bold(style), attrs}
  defp apply_style("italic", {style, attrs}), do: {Style.italic(style), attrs}
  defp apply_style("inverse", {style, attrs}), do: {Style.reverse(style), attrs}
  defp apply_style("reverse", {style, attrs}), do: {Style.reverse(style), attrs}
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

  defp apply_style("overflow-scroll", {style, attrs}),
    do: {Style.overflow(style, :scroll), attrs}

  defp apply_style("overflow-" <> overflow, {style, attrs}),
    do: {Style.overflow(style, String.to_existing_atom(overflow)), attrs}

  defp apply_style("offset-top-" <> num, {style, attrs}) do
    {_, left} = Map.get(attrs, :scroll, {0, 0})
    {style, Map.put(attrs, :scroll, {String.to_integer(num), left})}
  end

  defp apply_style("offset-left-" <> num, {style, attrs}) do
    {top, _} = Map.get(attrs, :scroll, {0, 0})
    {style, Map.put(attrs, :scroll, {top, String.to_integer(num)})}
  end

  defp apply_style("absolute", {style, attrs}), do: {style, Map.put(attrs, :position, :absolute)}

  defp apply_style("left-" <> num, {style, attrs}),
    do: {style, Map.put(attrs, :left, String.to_integer(num))}

  defp apply_style("top-" <> num, {style, attrs}),
    do: {style, Map.put(attrs, :top, String.to_integer(num))}

  defp apply_style("width-auto", {style, attrs}), do: {Style.width(style, :auto), attrs}
  defp apply_style("width-full", {style, attrs}), do: {Style.width(style, :full), attrs}
  defp apply_style("width-screen", {style, attrs}), do: {Style.width(style, :screen), attrs}

  defp apply_style("width-" <> num, {style, attrs}),
    do: {Style.width(style, String.to_integer(num)), attrs}

  defp apply_style("height-auto", {style, attrs}), do: {Style.height(style, :auto), attrs}
  defp apply_style("height-screen", {style, attrs}), do: {Style.height(style, :screen), attrs}
  defp apply_style("height-full", {style, attrs}), do: {Style.height(style, :full), attrs}

  defp apply_style("height-" <> num, {style, attrs}),
    do: {Style.height(style, String.to_integer(num)), attrs}

  defp apply_style("text-" <> num, {style, attrs}),
    do: {Style.foreground_color(style, String.to_integer(num)), attrs}

  defp apply_style("bg-" <> num, {style, attrs}),
    do: {Style.background_color(style, String.to_integer(num)), attrs}

  defp apply_style("scrollbar-none", {style, attrs}),
    do: {Style.scrollbar(style, false), attrs}

  defp apply_style("scrollbar-arrows", {style, attrs}),
    do: {Style.scrollbar(style, %{arrows: true}), attrs}

  defp apply_style("border-rounded", {style, attrs}),
    do: {Style.border(style, :rounded), attrs}

  defp apply_style("border-" <> num, {style, attrs}),
    do: {Style.border_color(style, String.to_integer(num)), attrs}

  defp apply_style(_, acc), do: acc
end
