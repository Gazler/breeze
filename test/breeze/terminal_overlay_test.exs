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
end
