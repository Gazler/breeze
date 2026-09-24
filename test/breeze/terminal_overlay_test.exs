defmodule Breeze.TerminalOverlayTest do
  use ExUnit.Case, async: true

  defmodule CaptureAdapter do
    def write(owner, data) do
      send(owner, {:output, data})
      {:ok, owner}
    end
  end

  test "trusted Kitty graphics overlays preserve transmission, animation, and deletion bytes" do
    commands = [
      "\e_Ga=T,f=100,i=1,m=1;YWJj\e\\\e_Gm=0;ZA==\e\\",
      "\e_Ga=a,i=1,s=3,v=1\e\\",
      "\e_Ga=d,d=A,q=2\e\\"
    ]

    terminal = %Termite.Terminal{adapter: {CaptureAdapter, self()}}

    for command <- commands do
      overlay = %{x: 2, y: 3, content: command}
      expected = "\e[4;3H" <> command <> "\e[4;3H"
      assert Breeze.TerminalOverlay.render_overlay(overlay) == expected
      Breeze.TerminalOverlay.write_overlays(terminal, [overlay])
      assert_receive {:output, ^expected}
    end
  end

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
