defmodule Breeze.Renderer do
  @moduledoc false

  alias BackBreeze.Box
  import NimbleParsec

  defparsecp(:parse_nodes, parsec(:node) |> eos())

  tag = ascii_string([?a..?z, ?_, ?A..?Z], min: 1)
  text = utf8_string([not: ?<], min: 1)

  attribute =
    ignore(string(" "))
    |> ascii_string([?a..?z, ?-], min: 1)
    |> ignore(string("="))
    |> ignore(string(~s(")))
    |> ascii_string([not: ?"], min: 1)
    |> ignore(string(~s(")))
    |> tag(:attribute)

  boolean_attribute =
    ignore(string(" "))
    |> ascii_string([?a..?z], min: 1)
    |> tag(:attribute_bool)

  opening_tag =
    ignore(string("<"))
    |> concat(tag)
    |> repeat(
      choice([
        attribute,
        boolean_attribute,
        ignore(string(">"))
      ])
    )

  closing_tag = ignore(string("</")) |> concat(tag) |> ignore(string(">"))

  padding = string("\n") |> repeat(choice([ascii_char([?\s]), string("\n")]))

  defcombinatorp(
    :node,
    opening_tag
    |> ignore(optional(padding))
    |> repeat(lookahead_not(string("</")) |> choice([parsec(:node), text]))
    |> wrap()
    |> concat(closing_tag)
    |> ignore(optional(padding))
    |> post_traverse(:match_and_emit_tag)
  )

  defp match_and_emit_tag(rest, [tag, [tag, text]], context, _line, _offset) do
    {rest, [{String.to_atom(tag), [], [text]}], context}
  end

  defp match_and_emit_tag(rest, [tag, [tag | nodes]], context, _line, _offset) do
    {rest, [{String.to_atom(tag), [], nodes}], context}
  end

  def render_to_string(mod, assigns, opts \\ []) do
    {_, %{content: content}} = render(mod, assigns, opts)
    content
  end

  def render(mod, assigns, opts \\ []) do
    {acc, box} =
      Phoenix.HTML.Safe.to_iodata(mod.render(assigns))
      |> IO.iodata_to_binary()
      |> parse(opts)

    {acc, BackBreeze.Box.render(box)}
  end

  def parse(data, opts \\ []) do
    {:ok, [{:box, _, children}], "", _, _, _} = parse_nodes(data)

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
    focusables = Enum.reverse(acc.focusables)
    focusables = Enum.filter(ids, fn id -> id in focusables end)

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
    # TODO: move the String.trim_trailing into the parser
    box = %{box | content: String.trim_trailing(content, "\n  ")}
    build_tree(rest, box, children, style, flags, acc, opts)
  end

  defp build_tree([{:box, _, nodes} | rest], box, children, style, flags, acc, opts) do
    child_flags =
      if Keyword.get(flags, :implicit) do
        [implicit_id: Keyword.fetch!(flags, :id)]
      else
        []
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
      (Keyword.get(flags, :id) || Keyword.get(flags, :implicit_id)) == Keyword.get(opts, :focused)

    flags = if focused, do: Keyword.put(flags, :focused, focused), else: flags

    style_opts =
      if focused do
        [focus: true]
      else
        []
      end

    implicit_state = Keyword.get(opts, :implicit_state, %{})
    implicit_id = Keyword.get(flags, :implicit_id)

    {implicit_mod, implicit} =
      case implicit_id && get_in(implicit_state, [implicit_id]) do
        nil -> {nil, nil}
        {mod, state} -> {mod, state}
      end

    style_opts =
      if implicit do
        modifiers = implicit_mod.handle_modifiers(flags, implicit)
        style_opts ++ modifiers
      else
        style_opts
      end

    focusables =
      if Keyword.get(flags, :focusable),
        do: [Keyword.get(flags, :id) | focusables],
        else: focusables

    element = string_to_styles(style, style_opts)
    opts = Map.put(element.attributes, :style, element.style)
    children = Enum.reverse(children)
    content = box.content
    acc = %{acc | focusables: focusables}
    {acc, %{Box.new(opts) | children: children, content: content}}
  end

  defp string_to_styles(str, opts) do
    map =
      String.split(str, " ")
      |> Enum.map(&String.split(&1, ":"))
      |> Enum.sort_by(&length/1)
      |> Enum.reduce(%{}, fn style, acc ->
        style =
          Enum.reduce_while(style, nil, fn
            "focus", _ -> if Keyword.get(opts, :focus), do: {:cont, nil}, else: {:halt, nil}
            "selected", _ -> if Keyword.get(opts, :selected), do: {:cont, nil}, else: {:halt, nil}
            other, _ -> {:halt, other}
          end)

        apply_style(style, acc)
      end)

    style_keys = Map.keys(Map.from_struct(%BackBreeze.Style{}))
    {style, attributes} = Map.split(map, style_keys)
    struct(Breeze.Element, %{style: style, attributes: attributes})
  end

  defp apply_style("border", acc), do: Map.put(acc, :border, :line)
  defp apply_style("bold", acc), do: Map.put(acc, :bold, true)
  defp apply_style("italic", acc), do: Map.put(acc, :italic, true)
  defp apply_style("inverse", acc), do: Map.put(acc, :reverse, true)
  defp apply_style("reverse", acc), do: Map.put(acc, :reverse, true)
  defp apply_style("inline", acc), do: Map.put(acc, :display, :inline)
  defp apply_style("absolute", acc), do: Map.put(acc, :position, :absolute)
  defp apply_style("left-" <> num, acc), do: Map.put(acc, :left, String.to_integer(num))
  defp apply_style("top-" <> num, acc), do: Map.put(acc, :top, String.to_integer(num))
  defp apply_style("width-" <> num, acc), do: Map.put(acc, :width, String.to_integer(num))
  defp apply_style("height-" <> num, acc), do: Map.put(acc, :height, String.to_integer(num))

  defp apply_style("text-" <> num, acc),
    do: Map.put(acc, :foreground_color, String.to_integer(num))

  defp apply_style("bg-" <> num, acc), do: Map.put(acc, :background_color, String.to_integer(num))
  defp apply_style("border-" <> num, acc), do: Map.put(acc, :border_color, String.to_integer(num))
  defp apply_style(_, acc), do: acc
end
