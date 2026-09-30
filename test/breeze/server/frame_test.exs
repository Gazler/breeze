defmodule Breeze.Server.FrameTest do
  use ExUnit.Case, async: true

  test "hidden offscreen cursor repairs its old row without clearing beyond the screen" do
    lines = List.duplicate("content", 23) ++ ["KEYBINDINGS"]
    previous = [%{x: 35, y: 21, char: " ", visible?: true}]
    hidden = [%{x: 35, y: 40, char: " ", visible?: false}]
    payload = Breeze.Server.Frame.build_payload(lines, lines, previous, hidden, 80)
    assert payload =~ "\e[22;1Hcontent"
    refute payload =~ "\e[41;"
    assert Breeze.Server.Frame.build_payload(lines, lines, hidden, [], 80) == ""
  end

  test "overlay row repairs are bounded to the screen" do
    lines = ["HEADER", "FOOTER"]
    previous = [%{x: 0, y: 50, char: "x"}, %{x: 0, y: -1, char: "x"}]
    assert Breeze.Server.Frame.build_payload(lines, lines, previous, [], 80) == ""
  end

  alias Breeze.Server.Frame

  test "row updates retain an unchanged suffix after a style reset at the same column" do
    suffix = "\e[0m\e[32m│" <> String.duplicate("shell", 40) <> "\e[0m"
    previous = "\e[31mold" <> suffix
    current = "\e[34mnew" <> suffix

    assert Frame.build_payload([previous], [current], [], [], 278) ==
             "\e[1;1H\e[34mnew\e[0m"
  end

  test "suffix reuse falls back when the unchanged suffix moves columns" do
    suffix = "\e[0m\e[32mshell\e[0m"
    previous = "\e[31mold" <> suffix
    current = "\e[34mlonger" <> suffix
    assert Frame.build_payload([previous], [current], [], [], 80) =~ current
  end

  test "overlay removal repaints the unchanged suffix too" do
    suffix = "\e[0m\e[32mshell\e[0m"
    previous = "\e[31mold" <> suffix
    current = "\e[34mnew" <> suffix
    overlay = %{x: 5, y: 0, char: "X"}
    assert Frame.build_payload([previous], [current], [overlay], [], 80) =~ current
  end

  test "suffix reuse does not split combining marks across a style reset" do
    suffix = "\e[0m\u0301tail"
    current = "\e[34me" <> suffix
    assert Frame.build_payload(["\e[31ma" <> suffix], [current], [], [], 80) =~ current
  end

  test "wide-glyph prepainting retains the full row" do
    suffix = "\e[0mshell\e[0m"
    current = "\e[34m👩‍💻" <> suffix
    assert Frame.build_payload(["\e[31m👩‍💻" <> suffix], [current], [], [], 80) =~ current
  end

  test "suffix reuse does not change the terminal's final active style" do
    suffix = "\e[0m\e[32mshell"
    current = "\e[34mnew" <> suffix
    assert Frame.build_payload(["\e[31mold" <> suffix], [current], [], [], 80) =~ current
  end

  test "input frame pacing includes time already spent rendering" do
    frame = %{last_render_started_at: 100, last_render_at: 112}
    assert Frame.input_render_delay(frame, 112, 16) == 4
    assert Frame.input_render_delay(frame, 116, 16) == 0
    assert Frame.input_render_delay(frame, 130, 16) == 0
    assert Frame.input_render_delay(%{last_render_at: nil}, 100, 16) == 0
    assert Frame.input_render_delay(%{last_render_at: 100}, 110, 16) == 6
  end

  test "wide checks retain combining marks with their ASCII base" do
    line = "a\u{1F3FB}"
    assert Frame.build_payload([""], [line], [], [], 1) == "\e[1;1H" <> line
  end

  test "wide-glyph checks do not allocate a grapheme list for full-width rows" do
    line = "│" <> String.duplicate("x", 276) <> "│"
    owner = self()

    worker =
      spawn_link(fn ->
        receive do
          :render -> send(owner, {:payload, Frame.build_payload(nil, [line], [], [], 278)})
        end

        receive do: (:stop -> :ok)
      end)

    :erlang.trace_pattern({String, :graphemes, 1}, true, [:local])
    :erlang.trace(worker, true, [:call])

    try do
      send(worker, :render)
      assert_receive {:payload, payload}, 1000
      delivery = :erlang.trace_delivered(worker)
      assert_receive {:trace_delivered, ^worker, ^delivery}
      assert payload == "\e[2J\e[H\e[1;1H" <> line
      refute_receive {:trace, ^worker, :call, {String, :graphemes, _}}, 0
    after
      :erlang.trace_pattern({String, :graphemes, 1}, false, [:local])
      send(worker, :stop)
    end
  end

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

  test "rows missing from the previous frame compare as empty" do
    assert Frame.build_payload(["same"], ["same", "new"], [], [], 10) ==
             "\e[2;1Hnew\e[2;4H\e[K"
  end

  test "rows beyond the current frame remain ignored" do
    assert Frame.build_payload(["same", "stale"], ["same"], [], [], 10) == ""
  end

  test "overlay repairs outside the current frame are skipped" do
    previous_overlay = %{x: 0, y: 3, height: 1, content: "old"}

    assert Frame.build_payload(["only"], ["only"], [previous_overlay], [], 10) == ""
  end

  test "child patches materialize complete rows without losing neighboring content" do
    viewport = %{left: 5, top: 0, width: 3, height: 1}

    assert Frame.patch_lines(["left old right"], "new", viewport, 20) == [
             "left new right      "
           ]
  end

  test "child patches preserve base output below the visible screen" do
    viewport = %{left: 5, top: 0, width: 3, height: 1}
    output = "left old right\nvisible tail\noff-screen one\noff-screen two"

    patched = Frame.patch_output(output, "new", viewport, 20)

    assert String.split(patched, "\n") == [
             "left new right      ",
             "visible tail",
             "off-screen one",
             "off-screen two"
           ]
  end

  test "historical lines are cropped without breaking ANSI styles" do
    assert Frame.fit_lines(["\e[31mabcdefgh\e[0m"], 4) == ["\e[31mabcd\e[0m"]
  end
end
