defmodule Breeze.Renderer do
  @moduledoc false

  alias BackBreeze.Box
  import NimbleParsec

  defparsecp(:parse_nodes, parsec(:node) |> eos())

  tag = ascii_string([?a..?z, ?A..?Z], min: 1)
  text = utf8_string([not: ?<], min: 1)

  attribute =
    ignore(string(" "))
    |> ascii_string([not: ?=], min: 1)
    |> ignore(string("="))
    |> ignore(string(~s(")))
    |> ascii_string([not: ?"], min: 1)
    |> ignore(string(~s(")))
    |> tag(:attribute)

  opening_tag = ignore(string("<")) |> concat(tag) |> optional(attribute) |> ignore(string(">"))
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

  def render_to_string(mod, assigns) do
    render(mod, assigns)
    |> Map.get(:content)
  end

  def render(mod, assigns) do
    Phoenix.HTML.Safe.to_iodata(mod.render(assigns))
    |> IO.iodata_to_binary()
    |> parse()
    |> BackBreeze.Box.render()
  end

  def parse(data) do
    {:ok, [{:box, _, children}], "", _, _, _} = parse_nodes(data)
    build_tree(children, %BackBreeze.Box{}, [])
  end

  defp build_tree([{:attribute, ["style", style]} | rest], _box, children) do
    element = string_to_styles(style)
    opts = Map.put(element.attributes, :style, element.style)
    build_tree(rest, Box.new(opts), children)
  end

  defp build_tree([content | rest], box, children) when is_binary(content) do
    # TODO: move the String.trim_trailing into the parser
    build_tree(rest, %{box | content: String.trim_trailing(content, "\n  ")}, children)
  end

  defp build_tree([{:box, _, nodes} | rest], box, children) do
    child = build_tree(nodes, %BackBreeze.Box{}, [])
    build_tree(rest, box, [child | children])
  end

  defp build_tree([], box, children) do
    %{box | children: Enum.reverse(children)}
  end

  defp string_to_styles(str) do
    map =
      String.split(str, " ")
      |> Enum.reduce(%{}, fn
        "border", acc -> Map.put(acc, :border, :line)
        "bold", acc -> Map.put(acc, :bold, true)
        "italic", acc -> Map.put(acc, :italic, true)
        "inverse", acc -> Map.put(acc, :reverse, true)
        "reverse", acc -> Map.put(acc, :reverse, true)
        "absolute", acc -> Map.put(acc, :position, :absolute)
        "left-" <> num, acc -> Map.put(acc, :left, String.to_integer(num))
        "top-" <> num, acc -> Map.put(acc, :top, String.to_integer(num))
        "width-" <> num, acc -> Map.put(acc, :width, String.to_integer(num))
        "height-" <> num, acc -> Map.put(acc, :height, String.to_integer(num))
        "text-" <> num, acc -> Map.put(acc, :foreground_color, String.to_integer(num))
        "bg-" <> num, acc -> Map.put(acc, :background_color, String.to_integer(num))
        _, acc -> acc
      end)

    style_keys = Map.keys(Map.from_struct(%BackBreeze.Style{}))
    {style, attributes} = Map.split(map, style_keys)
    struct(Breeze.Element, %{style: style, attributes: attributes})
  end
end
