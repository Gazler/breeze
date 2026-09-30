defmodule Breeze.TestSupport.TerminalScreenTest do
  use ExUnit.Case, async: true

  alias Breeze.TestSupport.TerminalScreen

  test "wrapping is delayed until the next printable character and scrolling preserves rows" do
    screen = TerminalScreen.new(%{width: 3, height: 2}) |> TerminalScreen.write("abcdef")
    assert TerminalScreen.rows(screen) == ["abc", "def"]
    assert TerminalScreen.scrollback(screen) == []

    screen = TerminalScreen.write(screen, "g")
    assert TerminalScreen.rows(screen) == ["def", "g"]
    assert TerminalScreen.scrollback(screen) == ["abc"]
  end

  test "carriage return cancels delayed wrapping and erasure affects only the addressed cells" do
    screen =
      TerminalScreen.new(%{width: 3, height: 2})
      |> TerminalScreen.write("abc\r\ndef\r\e[1;2H\e[K")

    assert TerminalScreen.rows(screen) == ["a", "def"]
    assert TerminalScreen.scrollback(screen) == []
    assert TerminalScreen.cursor(screen) == {1, 2}
    assert TerminalScreen.rows(TerminalScreen.write(screen, "\e[2K")) == ["", "def"]
  end

  test "unsupported controls fail explicitly" do
    assert_raise ArgumentError, ~r/unsupported terminal control/, fn ->
      TerminalScreen.new(%{width: 3, height: 2}) |> TerminalScreen.write("\e[?1049h")
    end
  end
end
