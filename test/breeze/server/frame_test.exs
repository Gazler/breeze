defmodule Breeze.Server.FrameTest do
  use ExUnit.Case, async: true

  alias Breeze.Server.Frame

  test "row patches prepaint styled backgrounds for wide glyph rows" do
    line = "\e[48;5;8mAこんにちはZ\e[0m"

    payload = Frame.build_payload([""], [line], [], [], 20)

    assert payload =~
             "\e[1;1H\e[48;5;8m            \e[0m\e[1;1H\e[48;5;8mAこんにちはZ\e[0m"
  end

  test "row patches do not prepaint ordinary ascii rows" do
    line = "\e[48;5;8mASCII\e[0m"

    assert Frame.build_payload([""], [line], [], [], 20) ==
             "\e[1;1H\e[48;5;8mASCII\e[0m\e[1;6H\e[K"
  end

  test "row patches re-emit multi-row overlays when covered rows change" do
    overlay = %{x: 4, y: 2, height: 3, content: "image-command"}
    previous_lines = ["one", "two", "three", "four", "five"]
    next_lines = ["one", "two", "three", "changed", "five"]

    payload = Frame.build_payload(previous_lines, next_lines, [overlay], [overlay], 20)

    assert payload =~ "\e[4;1Hchanged"
    assert payload =~ "\e[3;5Himage-command"
  end
end
