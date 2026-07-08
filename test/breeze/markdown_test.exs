defmodule Breeze.MarkdownTest do
  use ExUnit.Case, async: true

  alias Breeze.Markdown

  @reset "\e[0m"
  @heading "\e[30;43m"
  @code "\e[36m"
  @bold "\e[1m"

  describe "headings" do
    test "renders heading padded to width" do
      assert Markdown.render("# Hello", 10) == "#{@heading}# Hello   #{@reset}"
    end

    test "renders heading without trailing newlines when it is the only content" do
      result = Markdown.render("# Hi", 6)
      assert result == "#{@heading}# Hi  #{@reset}"
    end
  end

  describe "fenced code blocks" do
    test "renders fenced code block with indent and color" do
      doc = "```\nx = 1\n```"
      assert Markdown.render(doc, 20) == "#{@code}    x = 1#{@reset}"
    end

    test "renders multi-line fenced code block" do
      doc = "```elixir\nfoo\nbar\n```"
      assert Markdown.render(doc, 20) == "#{@code}    foo#{@reset}\n#{@code}    bar#{@reset}"
    end
  end

  describe "indented code blocks" do
    test "renders indented code with color" do
      doc = "    x = 1"
      assert Markdown.render(doc, 20) == "#{@code}    x = 1#{@reset}"
    end
  end

  describe "bullet lists" do
    test "renders bullet item with bullet character" do
      assert Markdown.render("* item", 20) == "• item"
    end

    test "supports - and + bullets" do
      assert Markdown.render("- item", 20) == "• item"
      assert Markdown.render("+ item", 20) == "• item"
    end

    test "consecutive bullets are not separated by blank line" do
      result = Markdown.render("* a\n* b", 20)
      assert result == "• a\n• b"
    end
  end

  describe "text wrapping" do
    test "wraps long lines at word boundaries" do
      result = Markdown.render("one two three four", 10)
      assert result == "one two\nthree four"
    end

    test "joins paragraph lines before wrapping" do
      result = Markdown.render("hello\nworld", 20)
      assert result == "hello world"
    end
  end

  describe "multiple blocks" do
    test "separates two paragraphs with a blank line" do
      result = Markdown.render("para one\n\npara two", 20)
      assert result == "para one\n\npara two"
    end

    test "heading followed by paragraph" do
      result = Markdown.render("# Title\n\nBody text", 20)
      assert result == "#{@heading}# Title             #{@reset}\n\nBody text"
    end

    test "wraps a long heading across multiple lines" do
      result = Markdown.render("# A B C D", 6)
      assert result == "#{@heading}# A B #{@reset}\n#{@heading}C D   #{@reset}"
    end
  end

  describe "inline formatting" do
    test "renders inline code" do
      result = Markdown.render("`foo`", 20)
      assert result == "#{@code}foo#{@reset}"
    end

    test "supports a custom reset sequence" do
      result = Markdown.render("`foo`.", 20, reset: "<restore>")
      assert result == "#{@code}foo<restore>."
    end

    test "renders bold text" do
      result = Markdown.render("**bold**", 20)
      assert result == "#{@bold}bold#{@reset}"
    end

    test "converts links to text with url" do
      result = Markdown.render("[Elixir](https://elixir-lang.org)", 50)
      assert result == "Elixir (https://elixir-lang.org)"
    end
  end

  describe "edge cases" do
    test "empty string returns empty string" do
      assert Markdown.render("", 20) == ""
    end

    test "wraps a long bullet item" do
      result = Markdown.render("* one two three four", 10)
      assert result == "• one two\n  three\n  four"
    end
  end
end
