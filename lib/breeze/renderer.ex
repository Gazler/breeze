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

  padding = string("\n") |> repeat(ascii_char([?\s]))

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
    %{style: style, attributes: attributes} =
      style
      |> Base.decode64!()
      |> Jason.decode!(keys: :atoms!)

    # TODO: allow strings for these values in backbreeze
    style =
      case Map.get(style, :border) do
        nil -> style
        border -> %{style | border: String.to_existing_atom(border)}
      end

    attributes =
      case Map.get(attributes, :position) do
        nil -> attributes
        position -> %{attributes | position: String.to_existing_atom(position)}
      end

    element = %Breeze.Element{style: style, attributes: attributes}
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
end
