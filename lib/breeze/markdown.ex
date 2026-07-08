defmodule Breeze.Markdown do
  @moduledoc false

  import BackBreeze.Utils, only: [string_length: 1]

  @reset "\e[0m"
  @heading "\e[30;43m"
  @code "\e[36m"
  @bold "\e[1m"
  @bullets [?*, ?-, ?+]

  def render(doc, width, opts \\ []) do
    reset = Keyword.get(opts, :reset, @reset)

    doc
    |> String.split(["\r\n", "\n"], trim: false)
    |> Enum.map(&String.trim_trailing/1)
    |> process([], "", width, reset)
    |> String.trim_trailing("\n")
  end

  defp process([], text, indent, width, reset), do: write_text(text, indent, width, reset)

  defp process(["" | rest], text, indent, width, reset) do
    write_text(text, indent, width, reset) <> process(rest, [], indent, width, reset)
  end

  defp process(["#" <> _ = heading | rest], text, indent, width, reset) do
    write_text(text, indent, width, reset) <>
      write_heading(heading, width, reset) <>
      process(rest, [], "", width, reset)
  end

  defp process(["```" <> _ | rest], text, indent, width, reset) do
    write_text(text, indent, width, reset) <> process_fenced_code(rest, [], indent, width, reset)
  end

  defp process(["    " <> line | rest], text, indent, width, reset) do
    write_text(text, indent, width, reset) <>
      process_indented_code(rest, [line], indent, width, reset)
  end

  defp process([<<bullet, ?\s, item::binary>> | rest], text, indent, width, reset)
       when bullet in @bullets do
    write_text(text, indent, width, reset) <> process_list("• ", item, rest, indent, width, reset)
  end

  defp process([line | rest], text, indent, width, reset) do
    process(rest, [line | text], indent, width, reset)
  end

  defp write_heading(heading, width, reset) do
    heading
    |> handle_inline(reset)
    |> String.split()
    |> wrap_words(width)
    |> Enum.map(fn line ->
      padding = String.duplicate(" ", max(width - string_length(line), 0))
      @heading <> line <> padding <> reset
    end)
    |> Enum.join("\n")
    |> Kernel.<>("\n\n")
  end

  defp process_fenced_code(["```" <> _ | rest], code, indent, width, reset) do
    write_code_block(Enum.reverse(code), reset) <> process(rest, [], indent, width, reset)
  end

  defp process_fenced_code([line | rest], code, indent, width, reset) do
    process_fenced_code(rest, [line | code], indent, width, reset)
  end

  defp process_fenced_code([], code, _indent, _width, reset) do
    write_code_block(Enum.reverse(code), reset)
  end

  defp process_indented_code(["    " <> line | rest], code, indent, width, reset) do
    process_indented_code(rest, [line | code], indent, width, reset)
  end

  defp process_indented_code(rest, code, indent, width, reset) do
    write_code_block(Enum.reverse(code), reset) <> process(rest, [], indent, width, reset)
  end

  defp write_code_block(lines, reset) do
    lines
    |> Enum.map(&(@code <> "    " <> &1 <> reset))
    |> Enum.join("\n")
    |> Kernel.<>("\n\n")
  end

  defp process_list(prefix, item, rest, indent, width, reset) do
    available = width - string_length(indent) - string_length(prefix)
    continuation = String.duplicate(" ", string_length(prefix))
    words = item |> handle_inline(reset) |> String.split()
    [first | more] = wrap_words(words, available)
    lines = [indent <> prefix <> first | Enum.map(more, &(indent <> continuation <> &1))]
    result = Enum.join(lines, "\n") <> "\n"

    case rest do
      [<<b, ?\s, _::binary>> | _] when b in @bullets ->
        result <> process(rest, [], indent, width, reset)

      _ ->
        result <> "\n" <> process(rest, [], indent, width, reset)
    end
  end

  defp write_text([], _indent, _width, _reset), do: ""

  defp write_text(text_lines, indent, width, reset) do
    available = width - string_length(indent)

    text_lines
    |> Enum.reverse()
    |> Enum.join(" ")
    |> handle_inline(reset)
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

  defp handle_inline(text, reset) do
    text
    |> remove_links()
    |> apply_inline(~r/`([^`]+)`/, @code, reset)
    |> apply_inline(~r/\*\*(.+?)\*\*/, @bold, reset)
  end

  defp apply_inline(text, pattern, color, reset) do
    Regex.replace(pattern, text, fn _, inner -> color <> inner <> reset end)
  end

  defp remove_links(text) do
    Regex.replace(~r{\[([^\]]*?)\]\((.*?)\)}, text, "\\1 (\\2)")
  end
end
