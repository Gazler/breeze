defmodule Breeze.Server.FrameTest do
  use ExUnit.Case, async: true

  alias Breeze.Server.Frame

  test "inline payload reserves rows and paints without clearing the screen" do
    payload = Frame.build_inline_payload(nil, ["one", "two"], [], [], 20, nil)

    assert payload =~ "\r\n"
    assert payload =~ "\e[1F"
    assert payload =~ "one"
    assert payload =~ "two"
    refute payload =~ "\e[2J"
    refute payload =~ "\e[1;1H"
  end

  test "inline payload is empty when lines and overlays are unchanged" do
    assert Frame.build_inline_payload(["one"], ["one"], [], [], 20, 1) == ""
  end

  test "inline payload growth reserves new rows below the current region" do
    payload = Frame.build_inline_payload(["one"], ["one", "two"], [], [], 20, 1)

    assert String.starts_with?(payload, "\e8\r\n")
    assert payload =~ "\e[1F"
  end

  test "inline scrollback clears the managed region then repaints it below output" do
    payload = Frame.build_inline_scrollback_payload("hello\n", ["prompt"], [], 20, 2)

    assert payload =~ "\e[1F"
    assert payload =~ "hello\r\n"
    assert payload =~ "prompt"
    refute payload =~ "\e[2J"
  end

  test "inline cursor overlay returns to the region bottom without moving to the cursor twice" do
    payload =
      Frame.build_inline_payload(
        ["status", "prompt", ""],
        ["status", "prompt", ""],
        [],
        [%{x: 4, y: 1, char: "x"}],
        20,
        3
      )

    assert count_occurrences(payload, "\e[1F\e[4C") == 1
    assert payload =~ "\r\e[1E"
  end

  defp count_occurrences(payload, pattern) do
    payload
    |> :binary.matches(pattern)
    |> length()
  end
end
