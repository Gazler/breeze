defmodule Breeze.HTMLFormatter do
  @moduledoc """
  `mix format` plugin for Breeze templates.

  This formatter supports the `~H` sigil and formats Breeze tags/components,
  attributes, slots, and directives (`:for`, `:if`).

  Add it to `.formatter.exs`:

      [
        plugins: [Breeze.HTMLFormatter],
        inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
      ]

  ## Prior art

  This module is inspired by Phoenix LiveView's HEEx formatter:

  * https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_view/html_formatter.ex
  """

  @behaviour Mix.Tasks.Format

  @default_line_length 98
  @void_elements ~w(area base br col embed hr img input link meta param source track wbr)

  @impl Mix.Tasks.Format
  def features(_opts) do
    [sigils: [:H], extensions: []]
  end

  @impl Mix.Tasks.Format
  def format(source, opts) do
    if opts[:sigil] == :H and opts[:modifiers] == ~c"noformat" do
      source
    else
      line_length = opts[:heex_line_length] || opts[:line_length] || @default_line_length

      formatted =
        source
        |> parse_template(opts)
        |> Map.fetch!(:nodes)
        |> format_nodes(0, line_length)
        |> normalize_blank_lines()
        |> trim_blank_edges()
        |> Enum.join("\n")

      newline =
        if match?(<<_>>, opts[:opening_delimiter] || "") or formatted in ["", []],
          do: "",
          else: "\n"

      formatted <> newline
    end
  end

  defp parse_template(source, opts) do
    env =
      __ENV__
      |> Macro.Env.prune_compile_info()
      |> Map.put(:file, Keyword.get(opts, :file, "nofile"))
      |> Map.put(:line, 1)

    Breeze.Template.parse!(source, env)
  end

  defp format_nodes(nodes, indent, line_length) when is_list(nodes) do
    nodes
    |> Enum.flat_map(&format_node(&1, indent, line_length))
    |> trim_blank_edges()
  end

  defp format_node({:text, segments}, indent, _line_length) do
    text = format_text_segments(segments)

    cond do
      text == "" ->
        []

      String.trim(text) == "" ->
        [""]

      true ->
        text
        |> String.split("\n", trim: false)
        |> Enum.map(fn
          "" -> ""
          line -> indent(indent) <> line
        end)
    end
  end

  defp format_node({:expr, expr}, indent, _line_length) do
    [indent(indent) <> "<%= " <> expr_to_string(expr) <> " %>"]
  end

  defp format_node({:element, name, attrs, directives, children}, indent, line_length) do
    attrs = collect_attrs(attrs, directives)

    cond do
      children == [] and self_closing?(name) ->
        format_opening(name, attrs, indent, line_length, "/>")

      inline = inline_children(children) ->
        one_line =
          indent(indent) <>
            "<" <> name <> join_attrs(attrs) <> ">" <> inline <> "</" <> name <> ">"

        if String.length(one_line) <= line_length do
          [one_line]
        else
          open = format_opening(name, attrs, indent, line_length, ">")
          child = format_nodes(children, indent + 2, line_length)
          close = [indent(indent) <> "</" <> name <> ">"]
          open ++ child ++ close
        end

      true ->
        open = format_opening(name, attrs, indent, line_length, ">")
        child = format_nodes(children, indent + 2, line_length)
        close = [indent(indent) <> "</" <> name <> ">"]
        open ++ child ++ close
    end
  end

  defp format_node(node, _indent, _line_length) do
    raise ArgumentError, "unsupported template node in Breeze.HTMLFormatter: #{inspect(node)}"
  end

  defp inline_children(children) do
    if Enum.all?(children, &simple_inline_node?/1) do
      children
      |> Enum.map(&inline_node_to_string/1)
      |> Enum.join("")
      |> case do
        "" -> nil
        content -> content
      end
    else
      nil
    end
  end

  defp simple_inline_node?({:text, _segments}), do: true
  defp simple_inline_node?({:expr, _expr}), do: true
  defp simple_inline_node?(_), do: false

  defp inline_node_to_string({:text, segments}), do: format_text_segments(segments)
  defp inline_node_to_string({:expr, expr}), do: "<%= " <> expr_to_string(expr) <> " %>"

  defp format_opening(name, attrs, indent_level, line_length, closer) do
    left = indent(indent_level)
    single_line = left <> "<" <> name <> join_attrs(attrs) <> closer

    if attrs == [] or String.length(single_line) <= line_length do
      [single_line]
    else
      [left <> "<" <> name] ++
        Enum.map(attrs, fn attr -> indent(indent_level + 2) <> attr end) ++
        [left <> closer]
    end
  end

  defp join_attrs([]), do: ""
  defp join_attrs(attrs), do: " " <> Enum.join(attrs, " ")

  defp collect_attrs(attrs, directives) do
    directive_attrs =
      []
      |> maybe_add_for(directives[:for])
      |> maybe_add_let(directives[:let])
      |> maybe_add_if(directives[:if])

    directive_attrs ++ Enum.map(attrs, &format_attr/1)
  end

  defp maybe_add_for(attrs, nil), do: attrs

  defp maybe_add_for(attrs, {pattern_string, _pattern_expr, enumerable_expr}) do
    attrs ++ [":for={" <> pattern_string <> " <- " <> expr_to_string(enumerable_expr) <> "}"]
  end

  defp maybe_add_if(attrs, nil), do: attrs
  defp maybe_add_if(attrs, expr), do: attrs ++ [":if={" <> expr_to_string(expr) <> "}"]

  defp maybe_add_let(attrs, nil), do: attrs

  defp maybe_add_let(attrs, {pattern_string, _pattern_expr}),
    do: attrs ++ [":let={" <> pattern_string <> "}"]

  defp format_attr({:boolean, name}), do: name

  defp format_attr({:static, name, value}) do
    value =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    name <> "=\"" <> value <> "\""
  end

  defp format_attr({:dynamic, name, expr}) do
    name <> "={" <> expr_to_string(expr) <> "}"
  end

  defp format_attr({:spread, expr}) do
    "{" <> expr_to_string(expr) <> "}"
  end

  defp normalize_blank_lines(lines) do
    {lines, _last_blank?} =
      Enum.reduce(lines, {[], false}, fn line, {acc, last_blank?} ->
        blank? = String.trim(line) == ""

        cond do
          blank? and last_blank? ->
            {acc, true}

          blank? ->
            {["" | acc], true}

          true ->
            {[line | acc], false}
        end
      end)

    Enum.reverse(lines)
  end

  defp trim_blank_edges(lines) do
    lines
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
  end

  defp self_closing?("." <> _), do: true
  defp self_closing?(name), do: name in @void_elements

  defp format_text_segments(segments) do
    Enum.map_join(segments, "", fn
      {:expr, expr} -> "{" <> expr_to_string(expr) <> "}"
      text when is_binary(text) -> text
    end)
  end

  defp expr_to_string(expr) do
    Macro.to_string(expr)
  end

  defp indent(level), do: String.duplicate(" ", level)
end
