defmodule Breeze.TerminalOverlayTest do
  use ExUnit.Case, async: true

  test "clear_line overlays clear the row before writing content" do
    output =
      Breeze.TerminalOverlay.render_overlay(%{
        x: 0,
        y: 3,
        content: "inspector",
        clear_line: true
      })

    assert output == "\e[4;1H\e[2Kinspector\e[4;1H"
  end

  test "no_wrap overlays disable autowrap while writing content" do
    output =
      Breeze.TerminalOverlay.render_overlay(%{
        x: 0,
        y: 3,
        content: "inspector",
        clear_line: true,
        no_wrap: true
      })

    assert output == "\e[4;1H\e[?7l\e[2Kinspector\e[?7h\e[4;1H"
  end
end
