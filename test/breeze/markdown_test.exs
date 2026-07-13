defmodule Breeze.MarkdownTest do
  use ExUnit.Case, async: true

  alias BackBreeze.TextSpan
  alias Breeze.Markdown
  alias Breeze.Renderer

  @heading_style %{foreground_color: 0, background_color: 3}
  @code_style %{foreground_color: 6}
  @bold_style %{bold: true}

  defmodule StyledMarkdownExample do
    use Breeze.View

    import Breeze.Blocks

    def render(assigns) do
      assigns = assign(assigns, content: "Before `inline code` after")

      ~H"""
      <.markdown
        id="markdown"
        content={@content}
        width={30}
        class="width-30 height-2"
        style={%{foreground_color: {4, 5, 6}, background_color: {1, 2, 3}}}
      />
      """
    end
  end

  describe "headings" do
    test "renders heading padded to width" do
      assert Markdown.render("# Hello", 10) == [TextSpan.new("# Hello   ", @heading_style)]
    end

    test "renders heading without trailing newlines when it is the only content" do
      assert Markdown.render("# Hi", 6) == [TextSpan.new("# Hi  ", @heading_style)]
    end
  end

  describe "fenced code blocks" do
    test "renders fenced code block with indent and color" do
      doc = "```\nx = 1\n```"
      assert Markdown.render(doc, 20) == [TextSpan.new("    x = 1", @code_style)]
    end

    test "renders multi-line fenced code block" do
      doc = "```elixir\nfoo\nbar\n```"

      assert Markdown.render(doc, 20) == [
               TextSpan.new("    foo", @code_style),
               TextSpan.new("\n"),
               TextSpan.new("    bar", @code_style)
             ]
    end
  end

  describe "indented code blocks" do
    test "renders indented code with color" do
      doc = "    x = 1"
      assert Markdown.render(doc, 20) == [TextSpan.new("    x = 1", @code_style)]
    end
  end

  describe "bullet lists" do
    test "renders bullet item with bullet character" do
      assert text(Markdown.render("* item", 20)) == "• item"
    end

    test "supports - and + bullets" do
      assert text(Markdown.render("- item", 20)) == "• item"
      assert text(Markdown.render("+ item", 20)) == "• item"
    end

    test "consecutive bullets are not separated by blank line" do
      result = Markdown.render("* a\n* b", 20)
      assert text(result) == "• a\n• b"
    end
  end

  describe "text wrapping" do
    test "wraps long lines at word boundaries" do
      result = Markdown.render("one two three four", 10)
      assert text(result) == "one two\nthree four"
    end

    test "joins paragraph lines before wrapping" do
      result = Markdown.render("hello\nworld", 20)
      assert text(result) == "hello world"
    end
  end

  describe "multiple blocks" do
    test "separates two paragraphs with a blank line" do
      result = Markdown.render("para one\n\npara two", 20)
      assert text(result) == "para one\n\npara two"
    end

    test "heading followed by paragraph" do
      assert Markdown.render("# Title\n\nBody text", 20) == [
               TextSpan.new("# Title             ", @heading_style),
               TextSpan.new("\n\nBody text")
             ]
    end

    test "wraps a long heading across multiple lines" do
      assert Markdown.render("# A B C D", 6) == [
               TextSpan.new("# A B ", @heading_style),
               TextSpan.new("\n"),
               TextSpan.new("C D   ", @heading_style)
             ]
    end
  end

  describe "inline formatting" do
    test "renders inline code" do
      assert Markdown.render("`foo`", 20) == [TextSpan.new("foo", @code_style)]
    end

    test "renders bold text" do
      assert Markdown.render("**bold**", 20) == [TextSpan.new("bold", @bold_style)]
    end

    test "converts links to text with url" do
      result = Markdown.render("[Elixir](https://elixir-lang.org)", 50)
      assert text(result) == "Elixir (https://elixir-lang.org)"
    end

    test "renders semantic spans for inherited component styles" do
      assert Markdown.render("Before `inline code` after", 40) == [
               TextSpan.new("Before "),
               TextSpan.new("inline code", %{foreground_color: 6}),
               TextSpan.new(" after")
             ]
    end

    test "preserves the component background through inline styles" do
      {_acc, box} =
        Renderer.render(StyledMarkdownExample, %{},
          terminal: %Termite.Terminal{size: %{width: 30, height: 2}}
        )

      assert box.content =~
               ~r/\e\[[0-9;]*48;2;1;2;3[0-9;]*m(?:\e\[[0-9;]*m)*inline code/
    end
  end

  describe "edge cases" do
    test "empty document returns no spans" do
      assert Markdown.render("", 20) == []
    end

    test "wraps a long bullet item" do
      result = Markdown.render("* one two three four", 10)
      assert text(result) == "• one two\n  three\n  four"
    end
  end

  defp text(spans), do: Enum.map_join(spans, & &1.text)
end
