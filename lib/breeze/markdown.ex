defmodule Breeze.Markdown do
  @moduledoc false

  alias BackBreeze.TextSpan

  import BackBreeze.Utils, only: [string_length: 1]

  @reset "\e[0m"
  @heading "\e[30;43m"
  @code "\e[36m"
  @bold "\e[1m"
  @bullets [?*, ?-, ?+]

  def render(doc, width) do
    doc
    |> render_ansi(width)
    |> spans_from_ansi()
  end

  defp render_ansi(doc, width) do
    doc
    |> String.split(["\r\n", "\n"], trim: false)
    |> Enum.map(&String.trim_trailing/1)
    |> process([], "", width)
    |> String.trim_trailing("\n")
  end

  defp process([], text, indent, width), do: write_text(text, indent, width)

  defp process(["" | rest], text, indent, width) do
    write_text(text, indent, width) <> process(rest, [], indent, width)
  end

  defp process(["#" <> _ = heading | rest], text, indent, width) do
    write_text(text, indent, width) <>
      write_heading(heading, width) <>
      process(rest, [], "", width)
  end

  defp process(["```" <> _ | rest], text, indent, width) do
    write_text(text, indent, width) <> process_fenced_code(rest, [], indent, width)
  end

  defp process(["    " <> line | rest], text, indent, width) do
    write_text(text, indent, width) <>
      process_indented_code(rest, [line], indent, width)
  end

  defp process([<<bullet, ?\s, item::binary>> | rest], text, indent, width)
       when bullet in @bullets do
    write_text(text, indent, width) <> process_list("• ", item, rest, indent, width)
  end

  defp process([line | rest], text, indent, width) do
    process(rest, [line | text], indent, width)
  end

  defp write_heading(heading, width) do
    heading
    |> handle_inline()
    |> String.split()
    |> wrap_words(width)
    |> Enum.map(fn line ->
      padding = String.duplicate(" ", max(width - string_length(line), 0))
      @heading <> line <> padding <> @reset
    end)
    |> Enum.join("\n")
    |> Kernel.<>("\n\n")
  end

  defp process_fenced_code(["```" <> _ | rest], code, indent, width) do
    write_code_block(Enum.reverse(code)) <> process(rest, [], indent, width)
  end

  defp process_fenced_code([line | rest], code, indent, width) do
    process_fenced_code(rest, [line | code], indent, width)
  end

  defp process_fenced_code([], code, _indent, _width) do
    write_code_block(Enum.reverse(code))
  end

  defp process_indented_code(["    " <> line | rest], code, indent, width) do
    process_indented_code(rest, [line | code], indent, width)
  end

  defp process_indented_code(rest, code, indent, width) do
    write_code_block(Enum.reverse(code)) <> process(rest, [], indent, width)
  end

  defp write_code_block(lines) do
    lines
    |> Enum.map(&(@code <> "    " <> &1 <> @reset))
    |> Enum.join("\n")
    |> Kernel.<>("\n\n")
  end

  defp process_list(prefix, item, rest, indent, width) do
    available = width - string_length(indent) - string_length(prefix)
    continuation = String.duplicate(" ", string_length(prefix))
    words = item |> handle_inline() |> String.split()
    [first | more] = wrap_words(words, available)
    lines = [indent <> prefix <> first | Enum.map(more, &(indent <> continuation <> &1))]
    result = Enum.join(lines, "\n") <> "\n"

    case rest do
      [<<b, ?\s, _::binary>> | _] when b in @bullets ->
        result <> process(rest, [], indent, width)

      _ ->
        result <> "\n" <> process(rest, [], indent, width)
    end
  end

  defp write_text([], _indent, _width), do: ""

  defp write_text(text_lines, indent, width) do
    available = width - string_length(indent)

    text_lines
    |> Enum.reverse()
    |> Enum.join(" ")
    |> handle_inline()
    |> String.split()
    |> wrap_words(available)
    |> Enum.map(&(indent <> &1))
    |> Enum.join("\n")
    |> Kernel.<>("\n\n")
  end

  defp wrap_words([], _width), do: [""]

  defp wrap_words(words, width) do
    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {lines, current} ->
        if current == "" do
          {lines, word}
        else
          candidate = current <> " " <> word

          if string_length(candidate) <= width do
            {lines, candidate}
          else
            {[current | lines], word}
          end
        end
      end)

    [current | lines] |> Enum.reverse()
  end

  defp handle_inline(text) do
    text
    |> remove_links()
    |> apply_inline(~r/`([^`]+)`/, @code)
    |> apply_inline(~r/\*\*(.+?)\*\*/, @bold)
  end

  defp apply_inline(text, pattern, color) do
    Regex.replace(pattern, text, fn _, inner -> color <> inner <> @reset end)
  end

  defp remove_links(text) do
    Regex.replace(~r{\[([^\]]*?)\]\((.*?)\)}, text, "\\1 (\\2)")
  end

  defp spans_from_ansi(text) do
    ~r/(\e\[[0-9;]*m)/
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.reduce({[], %{}}, fn
      @reset, {spans, _style} ->
        {spans, %{}}

      @heading, {spans, style} ->
        {spans, Map.merge(style, %{foreground_color: 0, background_color: 3})}

      @code, {spans, style} ->
        {spans, Map.put(style, :foreground_color, 6)}

      @bold, {spans, style} ->
        {spans, Map.put(style, :bold, true)}

      content, {spans, style} ->
        {[TextSpan.new(content, style) | spans], style}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
