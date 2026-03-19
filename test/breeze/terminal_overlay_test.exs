defmodule Breeze.TerminalOverlayTest do
  use ExUnit.Case, async: true

  alias Breeze.TerminalOverlay

  test "blink visibility toggles on 500ms boundaries" do
    assert TerminalOverlay.blink_visible?(0)
    refute TerminalOverlay.blink_visible?(500)
    assert TerminalOverlay.blink_visible?(1_000)
  end

  test "recent interaction keeps the cursor visible" do
    assert TerminalOverlay.visible?(500, 1)
    assert TerminalOverlay.visible?(999, 500)
    refute TerminalOverlay.visible?(1_500, 500)
  end

  test "char overlays can use explicit foreground and background colors" do
    assert TerminalOverlay.render_overlay(%{
             x: 1,
             y: 2,
             char: "X",
             foreground_color: "#111111",
             background_color: "#abcdef"
           }) ==
             "\e[3;2H\e[48;2;171;205;239;38;2;17;17;17mX\e[0m\e[3;2H"
  end
end
