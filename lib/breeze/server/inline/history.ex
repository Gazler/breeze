defmodule Breeze.Server.Inline.History do
  @moduledoc false

  @terminal_escape ~r/\e(?:\[[0-?]*[ -\/]*[@-~]|[\]PX^_].*?(?:\a|\e\\|$)|[ -\/]*[@-~])/s
  @text_style ~r/\A\e\[[0-9;:]*m\z/
  @hyperlink ~r/\A\e\]8;([^;\x00-\x1F\x7F-\x{9F}]*);([^\x00-\x1F\x7F-\x{9F}]*)(?:\a|\e\\)\z/u
  @close_link "\e]8;;\e\\"

  def rows(content, width) do
    tokens =
      content |> tokens() |> Enum.reverse() |> Enum.drop_while(&trailing?/1) |> Enum.reverse()

    {rows, row, _used, style} =
      Enum.reduce(tokens, {[], "", 0, %{sgr: "", link: ""}}, fn
        {:sgr, escape}, {rows, row, used, style} ->
          sgr = if escape in ["\e[m", "\e[0m"], do: "", else: style.sgr <> escape
          {rows, row <> escape, used, %{style | sgr: sgr}}

        {:link, link}, {rows, row, used, style} ->
          escape = if link == "", do: @close_link, else: link
          {rows, row <> escape, used, %{style | link: link}}

        "\n", {rows, row, _used, style} ->
          {[finish_row(row, style) | rows], reopen(style), 0, style}

        grapheme, {rows, row, used, style} ->
          cells = max(BackBreeze.Ucwidth.width(grapheme), 0)
          grapheme = if cells > width, do: "?", else: grapheme
          cells = min(cells, width)

          if used + cells > width do
            {[finish_row(row, style) | rows], reopen(style) <> grapheme, cells, style}
          else
            {rows, row <> grapheme, used + cells, style}
          end
      end)

    Enum.reverse([finish_row(row, style) | rows])
  end

  defp tokens(content) do
    content = content |> String.replace_invalid() |> String.replace("\r\n", "\n")

    @terminal_escape
    |> Regex.split(content, include_captures: true)
    |> Enum.flat_map(fn
      "\e" <> _ = escape ->
        escape_tokens(escape)

      text ->
        text
        |> String.replace(~r/[\x00-\x08\x0B-\x1F\x7F-\x{9F}]/u, "")
        |> String.replace("\t", "    ")
        |> String.graphemes()
    end)
  end

  # Only SGR and complete OSC 8 sequences with control-free parameters and
  # targets may reach the terminal. Never repair a malformed escape into one.
  defp escape_tokens(escape) do
    if Regex.match?(@text_style, escape) do
      [{:sgr, escape}]
    else
      case Regex.run(@hyperlink, escape) do
        [_, _params, ""] -> [{:link, ""}]
        [_, params, uri] -> [{:link, "\e]8;" <> params <> ";" <> uri <> "\e\\"}]
        _ -> []
      end
    end
  end

  defp trailing?({_type, _escape}), do: true
  defp trailing?("\n"), do: true
  defp trailing?(_), do: false

  defp reopen(style), do: style.sgr <> style.link

  # Close attributes before newlines so scroll fill and the live frame cannot
  # inherit a background or a hyperlink. Restore them on the next history row.
  defp finish_row(row, style) do
    row <>
      if(style.link == "", do: "", else: @close_link) <>
      if(style.sgr == "", do: "", else: "\e[0m")
  end
end
