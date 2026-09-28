defmodule Breeze.Server.InlineTest do
  use ExUnit.Case, async: true

  alias Breeze.Server.Inline
  alias Breeze.TestSupport.TerminalScreen

  test "starts below existing text and uses only its own rows" do
    {inline, "\r\n"} = Inline.open(%{width: 20, height: 10}, {4, 7})
    {inline, payload, lines, []} = Inline.render(inline, nil, ["hello", "world"], [], [])

    assert inline.top == 4
    assert inline.height == 2
    assert payload =~ "\e[5;1Hhello"
    assert payload =~ "\e[6;1Hworld"
    assert String.starts_with?(payload, "\e[?2026h")
    assert String.ends_with?(payload, "\e[5;1H\e[?2026l")
    refute payload =~ "\e[2J"
    refute payload =~ "\e[H"
    assert {^inline, "", ^lines, []} = Inline.render(inline, lines, lines, [], [])
  end

  test "growing at the bottom scrolls existing output up and translates overlays" do
    {inline, _} = Inline.open(%{width: 20, height: 10}, {10, 1})
    {inline, _, lines, _} = Inline.render(inline, nil, ["first"], [], [])
    overlay = %{x: 2, y: 2, char: "_"}

    {inline, payload, _, _} =
      Inline.render(inline, lines, ["first", "second", "third"], [], [overlay])

    assert inline.top == 7
    assert inline.height == 3
    assert String.starts_with?(payload, "\e[?2026h\e[10;1H\r\n\r\n")
    assert payload =~ "\e[9;1Hsecond"
    assert payload =~ "\e[10;3H"
    refute payload =~ "\e[2J"
  end

  test "shrinking clears vacated rows without moving into earlier output" do
    {inline, _} = Inline.open(%{width: 20, height: 10}, {5, 1})
    {inline, _, lines, _} = Inline.render(inline, nil, ["first", "second", "third"], [], [])
    {inline, payload, ["first"], []} = Inline.render(inline, lines, ["first"], [], [])

    assert inline.top == 4
    assert inline.height == 1
    assert payload =~ "\e[6;1H\e[6;1H\e[K"
    assert payload =~ "\e[7;1H\e[7;1H\e[K"
    assert String.ends_with?(payload, "\e[5;1H\e[?2026l")
  end

  test "fixed height supplies a bounded layout and auto height preserves intentional blank rows" do
    {inline, _} = Inline.open(%{width: 20, height: 10}, {5, 1}, 3)
    assert Inline.layout_size(inline) == %{width: 20, height: 3}
    assert Inline.lines(inline, "one") == ["one", "", ""]
    resized = Inline.resize(inline, %{width: 12, height: 2}, {2, 1})
    assert Inline.layout_size(resized) == %{width: 12, height: 2}

    {inline, _} = Inline.open(%{width: 20, height: 10}, {5, 1})
    assert Inline.lines(inline, "one\n\n") == ["one", "", ""]
  end

  test "resize uses the reported origin after terminal reflow" do
    {inline, _} = Inline.open(%{width: 20, height: 10}, {5, 1})
    {inline, _, _, _} = Inline.render(inline, nil, ["one", "two", "three"], [], [])
    inline = Inline.resize(inline, %{width: 10, height: 5}, {4, 1})
    assert inline.top == 3
    assert inline.height == 0
    {inline, payload, _, _} = Inline.render(inline, nil, ["one", "two", "three"], [], [])
    assert payload =~ "\e[4;1H\e[0m\e[J"

    inline = Inline.resize(inline, %{width: 10, height: 2}, {2, 1})
    {inline, _, _, _} = Inline.render(inline, nil, ["one", "two"], [], [])
    assert inline.top == 0
    assert inline.height == 2
  end

  for reflow? <- [true, false] do
    test "narrowing clears the old frame and preserves history (reflow: #{reflow?})" do
      size = %{width: 18, height: 16}
      screen = TerminalScreen.new(size, ["shell", "history"])
      {inline, _} = Inline.open(size, {3, 1})

      {inline, payload, _, _} =
        Inline.render(inline, nil, List.duplicate("123456789abcdefghi", 3), [], [])

      screen = TerminalScreen.write(screen, payload)

      for width <- [12, 8, 4] do
        resized = %{size | width: width}
        screen = TerminalScreen.resize(screen, resized, reflow: unquote(reflow?))
        inline = Inline.resize(inline, resized, TerminalScreen.cursor(screen))
        {inline, payload, _, _} = Inline.render(inline, nil, ["new", "ui"], [], [])
        screen = TerminalScreen.write(screen, payload)

        assert Enum.slice(TerminalScreen.rows(screen), inline.top, 2) == ["new", "ui"]
        assert Enum.all?(Enum.drop(TerminalScreen.rows(screen), inline.top + 2), &(&1 == ""))
        refute payload =~ "\e[2J"
        refute payload =~ "\e[3J"
        assert TerminalScreen.scrollback(screen) == []
      end
    end
  end

  test "prompt redraw discards the live frame before reflow while retaining completed history" do
    size = %{width: 12, height: 10}
    screen = TerminalScreen.new(size, ["shell"])
    {inline, _} = Inline.open(size, {2, 1})
    inline = Inline.append(inline, "completed")

    {inline, payload, _, _} =
      Inline.render(inline, nil, List.duplicate("OLD012345678", 3), [], [])

    screen = TerminalScreen.write(screen, payload)
    resized = %{size | width: 6}
    screen = TerminalScreen.resize(screen, resized, redraw_prompt: true)

    assert TerminalScreen.rows(screen) == ["shell", "comple", "ted", "", "", "", "", "", "", ""]
    assert TerminalScreen.scrollback(screen) == []

    inline = Inline.resize(inline, resized, TerminalScreen.cursor(screen))
    {inline, payload, _, _} = Inline.render(inline, nil, ["new"], [], [])
    screen = TerminalScreen.write(screen, payload)
    assert Enum.take(TerminalScreen.rows(screen), 4) == ["shell", "comple", "ted", "new"]

    {_, payload} = inline |> Inline.append("done") |> Inline.take_pending_output()

    screen =
      screen
      |> TerminalScreen.write(payload)
      |> TerminalScreen.resize(resized, redraw_prompt: true)

    assert Enum.take(TerminalScreen.rows(screen), 4) == ["shell", "comple", "ted", "done"]
  end

  test "missing cursor reports scroll to a known blank position without clearing history" do
    {inline, payload} = Inline.open(%{width: 20, height: 4}, nil)
    assert payload == "\r\n\n\n\n"
    assert inline.top == 3
    assert inline.height == 0
  end

  test "history clears only the live region and wraps wide graphemes by cell width" do
    {inline, _} = Inline.open(%{width: 5, height: 8}, {5, 1})
    {inline, _, _, _} = Inline.render(inline, nil, ["live", "old"], [], [])
    inline = Inline.append(inline, "ab界cd\nnext\n")
    {inline, payload} = Inline.take_pending_output(inline)

    assert inline.top == 7
    assert inline.height == 0
    assert payload =~ "\e[5;1H\e[0m\e[2K\e[6;1H\e[0m\e[2K"
    assert String.ends_with?(payload, "ab界c\r\nd\r\nnext\r\n")
    refute payload =~ "\e[2J"
  end

  test "mouse events use local coordinates and ignore history rows" do
    {inline, _} = Inline.open(%{width: 20, height: 10}, {5, 1})
    {inline, _, _, _} = Inline.render(inline, nil, ["one", "two"], [], [])
    assert Inline.translate_mouse(inline, %{"x" => 2, "y" => 4}) == %{"x" => 2, "y" => 0}
    assert Inline.translate_mouse(inline, %{"x" => 2, "y" => 3}) == nil
    assert Inline.translate_mouse(inline, %{"x" => 2, "y" => 6}) == nil
  end

  test "oversized live rows are clipped before they can wrap into other rows" do
    {inline, _} = Inline.open(%{width: 4, height: 8}, {5, 1})
    {_, payload, [line], _} = Inline.render(inline, nil, ["\e[31mabcdef\e[0m"], [], [])
    assert line == "\e[31mabcd\e[0m"
    refute payload =~ "abcdef"
  end

  test "history preserves styles and hyperlinks while removing screen controls" do
    {inline, _} = Inline.open(%{width: 80, height: 10}, {1, 1})
    text = "\e[31mred\e[0m \e[2Jvisible \e]8;;https://example.com\e\\link\e]8;;\e\\"
    {_, payload} = inline |> Inline.append(text) |> Inline.take_pending_output()

    assert payload ==
             "\e[1;1H\e]133;C\e\\\e[0m\e[31mred\e[0m visible \e]8;;https://example.com\e\\link\e]8;;\e\\\r\n"
  end

  test "colored hyperlinks wrap by visible cells and close before later output" do
    for terminator <- ["\a", "\e\\"] do
      {inline, _} = Inline.open(%{width: 4, height: 10}, {1, 1})
      open = "\e]8;id=docs;https://example.com/path;a=1#{terminator}"
      link = "\e]8;id=docs;https://example.com/path;a=1\e\\"
      close = "\e]8;;\e\\"

      {inline, payload} =
        inline
        |> Inline.append("\e[31m#{open}ab界cd\nEF")
        |> Inline.append("next")
        |> Inline.take_pending_output()

      assert inline.top == 4

      assert payload ==
               "\e[1;1H\e]133;C\e\\\e[0m\e[31m#{link}ab界#{close}\e[0m\r\n\e[31m#{link}cd#{close}\e[0m\r\n\e[31m#{link}EF#{close}\e[0m\r\n\e[4;1H\e]133;C\e\\\e[0mnext\r\n"
    end
  end

  test "SGR reset leaves an active link intact and closing a link leaves color intact" do
    link = "\e]8;;https://example.com\e\\"
    close = "\e]8;;\e\\"

    assert Breeze.Server.Inline.History.rows("#{link}\e[31mA\e[0mB#{close}C", 1) == [
             "#{link}\e[31mA\e[0m#{close}",
             "#{link}B#{close}",
             "C"
           ]

    assert Breeze.Server.Inline.History.rows("\e[31m#{link}A#{close}B", 1) == [
             "\e[31m#{link}A#{close}\e[0m",
             "\e[31mB\e[0m"
           ]
  end

  test "hyperlinks reject incomplete sequences and control characters in their targets or parameters" do
    for command <- [
          "\e]8;;https://example.com",
          "\e]8;;https://example.com\e[2J\e\\",
          "\e]8;id=\ninvalid;https://example.com\a",
          "\e]8;;https://example.com/\u009b2J\a",
          "\e]8;;https://example.com/\r\n\a",
          "\e]52;c;clipboard\a",
          "\e]0;title\a"
        ] do
      assert Breeze.Server.Inline.History.rows("before" <> command, 80) == ["before"]
    end
  end

  test "styled history wraps by display cells and reapplies styles after each row" do
    for style <- [
          "\e[1;31m",
          "\e[38;5;196m",
          "\e[38;2;255;80;20m",
          "\e[38:2::255:80:20m",
          "\e[48;2;20;30;40m"
        ] do
      {inline, _} = Inline.open(%{width: 4, height: 8}, {1, 1})

      {inline, payload} =
        inline
        |> Inline.append(style <> "ab界cd\n\e[0m")
        |> Inline.take_pending_output()

      assert inline.top == 2
      assert payload == "\e[1;1H\e]133;C\e\\\e[0m#{style}ab界\e[0m\r\n#{style}cd\e[0m\r\n"
    end
  end

  test "partial style resets survive wrapping and explicit newlines" do
    {inline, _} = Inline.open(%{width: 2, height: 8}, {1, 1})

    {inline, payload} =
      inline
      |> Inline.append("\e[1mAB\e[22;31mCD\nEF")
      |> Inline.take_pending_output()

    assert inline.top == 3
    assert payload =~ "\e[0m\r\n\e[1m\e[22;31mCD\e[0m\r\n"
    assert String.ends_with?(payload, "\e[1m\e[22;31mEF\e[0m\r\n")
  end

  test "history preserves RGB tuples and hex colors rendered by Termite" do
    for color <- [{255, 85, 17}, "#ff5511", "#f51"] do
      {inline, _} = Inline.open(%{width: 80, height: 10}, {1, 1})

      text =
        Termite.Style.foreground(color)
        |> Termite.Style.render_to_string("colored")

      {_, payload} = inline |> Inline.append(text) |> Inline.take_pending_output()
      assert payload == "\e[1;1H\e]133;C\e\\\e[0m\e[38;2;255;85;17mcolored\e[0m\r\n"
    end
  end

  test "styles do not leak into later history or the live frame" do
    size = %{width: 10, height: 6}
    screen = TerminalScreen.new(size, ["shell"])
    {inline, _} = Inline.open(size, {2, 1})

    inline =
      inline
      |> Inline.append("\e[31;44mred")
      |> Inline.append("plain")

    {inline, payload, _, _} = Inline.render(inline, nil, ["live"], [], [])
    assert payload =~ "\e[31;44mred\e[0m\r\n\e[3;1H\e]133;C\e\\\e[0mplain\r\n"
    assert inline.top == 3

    screen = TerminalScreen.write(screen, payload)
    assert TerminalScreen.rows(screen) == ["shell", "red", "plain", "live", "", ""]
    assert TerminalScreen.cursor(screen) == {4, 1}
  end

  test "history strips non-style commands even when they occur between styled text" do
    {inline, _} = Inline.open(%{width: 80, height: 10}, {1, 1})

    text =
      "\e[32ma\e[99;99Hb\e[?1049hc\e]52;c;payload\ad\ePpayload\e\\e\e[>4mf\b\t\r\ng\e[m\n"

    {inline, payload} = inline |> Inline.append(text) |> Inline.take_pending_output()
    assert payload == "\e[1;1H\e]133;C\e\\\e[0m\e[32mabcdef    \e[0m\r\n\e[32mg\e[0m\r\n"
    assert inline.top == 2
  end

  test "malformed escapes and C1 controls cannot introduce terminal commands" do
    for content <- [
          "before\e[31",
          "before\e[3\b1mhidden",
          "before\e\e[2Jafter",
          "before\e]52;c;clipboard",
          "before\eP\e[2J\e\\after",
          "before\u009b2Jafter\u009d52;c;clipboard\u009c",
          "before" <> <<0x9B>> <> "2Jafter"
        ] do
      {inline, _} = Inline.open(%{width: 80, height: 10}, {1, 1})
      {_, payload} = inline |> Inline.append(content) |> Inline.take_pending_output()
      assert String.starts_with?(payload, "\e[1;1H\e]133;C\e\\\e[0mbefore")

      history = String.replace_prefix(payload, "\e[1;1H\e]133;C\e\\\e[0m", "")
      assert String.valid?(history)
      refute history =~ ~r/[\x00-\x09\x0B\x0C\x0E-\x1F\x7F-\x{9F}]/u
    end
  end

  test "resize updates physical and available sizes together before applying the height cap" do
    override = fn size -> %{size | height: size.height - 1} end
    {inline, _} = Inline.open(%{width: 20, height: 10}, {5, 1}, 4, override)
    assert inline.physical_size.height == 10
    assert inline.available_size.height == 9
    assert Inline.layout_size(inline).height == 4

    inline = Inline.resize(inline, %{width: 12, height: 3}, {3, 1}, override)
    assert inline.physical_size == %{width: 12, height: 3}
    assert inline.available_size == %{width: 12, height: 2}
    assert Inline.layout_size(inline) == %{width: 12, height: 2}

    {inline, _} = Inline.take_pending_output(inline)
    inline = Inline.resize(inline, %{width: 15, height: 8}, nil, override)
    assert inline.physical_size == %{width: 15, height: 8}
    assert inline.available_size == %{width: 15, height: 7}
    assert Inline.layout_size(inline) == %{width: 15, height: 4}
    assert Inline.pending_output?(inline)
  end

  test "resize rejects queued output instead of losing it or reanchoring an uncommitted frame" do
    size = %{width: 20, height: 10}
    {inline, _} = Inline.open(size, {5, 1})
    inline = inline |> Inline.append("first") |> Inline.append("second")

    for position <- [nil, {5, 1}] do
      assert_raise ArgumentError, "flush pending inline output before resizing", fn ->
        Inline.resize(inline, size, position)
      end
    end

    {inline, payload, _, _} = Inline.render(inline, nil, ["live"], [], [])
    assert payload =~ "first\r\n"
    assert payload =~ "second\r\n"
    refute Inline.pending_output?(inline)
    assert Inline.resize(inline, size, {7, 1}).top == 6
  end

  test "screen contents survive growth, physical scrolling and shrinkage with a layout override" do
    size = %{width: 20, height: 6}
    screen = TerminalScreen.new(size, ["history 1", "history 2", "history 3", "history 4"])
    override = fn size -> %{size | height: size.height - 1} end
    {inline, _} = Inline.open(size, {5, 1}, :auto, override)
    {inline, payload, previous, _} = Inline.render(inline, nil, ["ready"], [], [])
    screen = TerminalScreen.write(screen, payload)

    {inline, payload, previous, _} = Inline.render(inline, previous, ["ready", "second"], [], [])
    screen = TerminalScreen.write(screen, payload)

    assert TerminalScreen.rows(screen) ==
             ["history 1", "history 2", "history 3", "history 4", "ready", "second"]

    assert TerminalScreen.scrollback(screen) == []

    {inline, payload, previous, _} =
      Inline.render(inline, previous, ["ready", "second", "third"], [], [])

    screen = TerminalScreen.write(screen, payload)

    assert TerminalScreen.rows(screen) == [
             "history 2",
             "history 3",
             "history 4",
             "ready",
             "second",
             "third"
           ]

    assert TerminalScreen.scrollback(screen) == ["history 1"]

    {_, payload, _, _} = Inline.render(inline, previous, ["ready"], [], [])
    screen = TerminalScreen.write(screen, payload)
    assert TerminalScreen.rows(screen) == ["history 2", "history 3", "history 4", "ready", "", ""]
    assert TerminalScreen.cursor(screen) == {4, 1}
  end

  for cursor_reply? <- [true, false] do
    test "screen retains queued history across resize (cursor reply: #{cursor_reply?})" do
      size = %{width: 20, height: 6}
      screen = TerminalScreen.new(size, ["shell", "earlier"])
      {inline, _} = Inline.open(size, {3, 1})
      {inline, payload, _, _} = Inline.render(inline, nil, ["ready"], [], [])
      screen = TerminalScreen.write(screen, payload)
      inline = inline |> Inline.append("first") |> Inline.append("second")
      {inline, payload, _, _} = Inline.render(inline, nil, ["ready"], [], [])
      screen = TerminalScreen.write(screen, payload)

      position = if unquote(cursor_reply?), do: TerminalScreen.cursor(screen)
      inline = Inline.resize(inline, size, position)
      {_, payload, _, _} = Inline.render(inline, nil, ["updated"], [], [])
      screen = TerminalScreen.write(screen, payload)

      if unquote(cursor_reply?) do
        assert TerminalScreen.rows(screen) == [
                 "shell",
                 "earlier",
                 "first",
                 "second",
                 "updated",
                 ""
               ]

        assert TerminalScreen.scrollback(screen) == []
      else
        assert TerminalScreen.rows(screen) == ["", "", "", "", "", "updated"]

        assert TerminalScreen.scrollback(screen) == [
                 "shell",
                 "earlier",
                 "first",
                 "second",
                 "ready"
               ]
      end
    end
  end

  test "reanchoring after a history-only flush keeps the cursor's blank row available" do
    size = %{width: 20, height: 6}
    screen = TerminalScreen.new(size, ["shell", "earlier"])
    {inline, _} = Inline.open(size, {3, 1})
    {inline, payload} = inline |> Inline.append("history") |> Inline.take_pending_output()
    screen = TerminalScreen.write(screen, payload)
    inline = Inline.resize(inline, size, TerminalScreen.cursor(screen))
    {_, payload, _, _} = Inline.render(inline, nil, ["live"], [], [])
    screen = TerminalScreen.write(screen, payload)
    assert TerminalScreen.rows(screen) == ["shell", "earlier", "history", "live", "", ""]
  end
end
