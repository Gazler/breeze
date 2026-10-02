defmodule Breeze.Server.ScrollFrameTest do
  use ExUnit.Case, async: true
  alias Breeze.Server.{Frame, ScrollFrame}

  defp frames do
    rows = for n <- 1..13, do: String.pad_trailing("line #{n}", 65, ".")

    frame = fn rows ->
      Enum.with_index(rows, fn row, i -> "#{rem(i, 10)} side │" <> "\e[32m" <> row <> "\e[0m" end)
    end

    {frame.(Enum.take(rows, 12)), frame.(tl(rows))}
  end

  defp build(old, new, regions, previous_overlays \\ [], overlays \\ []) do
    baseline = Frame.build_payload(old, new, previous_overlays, overlays, 73)
    ScrollFrame.build(old, new, previous_overlays, overlays, 73, regions, baseline)
  end

  test "scroll is opt-in and bounded to its container, repairing the adjacent panel" do
    {old, new} = frames()
    assert build(old, new, []).mode == :default
    result = build(old, new, [%{left: 8, top: 0, width: 65, height: 12}])
    assert result.mode == :scroll
    assert result.payload =~ "\e[1S"
    assert result.payload =~ "\e[1;1H\e[0m0"
    assert byte_size(result.payload) < result.baseline_bytes
    assert build(old, new, [%{left: 0, top: 0, width: 8, height: 12}]).mode == :default
  end

  test "scroll down, multiple rows, and fixed header/footer inside the container" do
    {old, new} = frames()
    region = [%{left: 8, top: 0, width: 65, height: 14}]
    result = build(["HEADER" | new] ++ ["FOOTER"], ["HEADER" | old] ++ ["FOOTER"], region)
    assert result.mode == :scroll
    assert result.payload =~ "\e[2;13r"
    assert result.payload =~ "\e[1T"
    new = Enum.drop(old, 2) ++ ["new row", "another row"]
    assert build(old, new, [%{left: 8, top: 0, width: 65, height: 12}]).payload =~ "\e[2S"
  end

  test "left-panel scrolling repairs the right panel, and multiple opt-ins choose the smaller payload" do
    rows = Enum.map(1..13, &String.pad_trailing("item #{&1}", 65, "."))
    frame = fn rows -> Enum.with_index(rows, fn row, i -> row <> "│right #{rem(i, 10)}" end) end
    old = frame.(Enum.take(rows, 12))
    new = frame.(tl(rows))
    left = %{left: 0, top: 0, width: 65, height: 12}
    right = %{left: 65, top: 0, width: 8, height: 12}
    result = build(old, new, [right, left])
    assert result.mode == :scroll
    assert result.payload =~ "\e[1;73H\e[0m0"
    assert build(old, new, [right]).mode == :default
  end

  test "unknown control sequences, wide characters and content overlays use the baseline unchanged" do
    {old, new} = frames()
    regions = [%{left: 8, top: 0, width: 65, height: 12}]

    for text <- ["\e]8;;https://example.com\aurl", "\ttext", "界", "é"] do
      next = List.replace_at(new, 0, text)
      assert build(old, next, regions).payload == Frame.build_payload(old, next, [], [], 73)
    end

    overlay = %{x: 0, y: 0, content: "modal"}
    assert build(old, new, regions, [overlay], [overlay]).mode == :default
  end

  test "unchanged frames, first render, invalid bounds and wide glyphs fall back" do
    {old, new} = frames()
    regions = [%{left: 8, top: 0, width: 65, height: 12}]
    assert build(old, old, regions).payload == ""
    assert build(nil, new, regions).mode == :default
    assert build(old, new, [%{left: -1, top: 0, width: 65, height: 12}]).mode == :default
    assert build(old, List.replace_at(new, 0, "👩‍💻"), regions).mode == :default
  end

  test "cursor overlays are repainted after scrolling and their moved rows are repaired" do
    {old, new} = frames()
    cursor = %{x: 15, y: 5, char: "X"}
    result = build(old, new, [%{left: 8, top: 0, width: 65, height: 12}], [cursor], [cursor])
    assert result.mode == :scroll
    assert result.payload =~ "\e[5;1H"
    assert result.payload =~ Breeze.TerminalOverlay.render_overlay(cursor)
  end
end
