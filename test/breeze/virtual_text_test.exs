defmodule Breeze.VirtualTextTest do
  use ExUnit.Case, async: true

  test "renders virtual text near the end of a fixed-height viewport" do
    content =
      1..2_000
      |> Enum.map_join("\n", fn index ->
        "Line #{index}" |> String.pad_trailing(12, ".")
      end)
      |> BackBreeze.VirtualText.new()

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(14)
      |> BackBreeze.Style.height(5)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content, offset_top: 1_996)

    assert output ==
             """
             ┌────────────┐
             │Line 1997...│
             │Line 1998...│
             │Line 1999...│
             └────────────┘\
             """
  end

  test "renders lazy virtual text near the end of a fixed-height viewport" do
    content =
      BackBreeze.VirtualText.lazy(
        cache_key: :lazy_virtual_text_fixture,
        intrinsic_width: 12,
        line_count_fn: fn _width -> 2_000 end,
        slice_fn: fn start_line, count, _width ->
          Enum.map(start_line..(start_line + count - 1), fn index ->
            "Line #{index + 1}" |> String.pad_trailing(12, ".")
          end)
        end
      )

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(14)
      |> BackBreeze.Style.height(5)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content, offset_top: 1_996)

    assert output ==
             """
             ┌────────────┐
             │Line 1997...│
             │Line 1998...│
             │Line 1999...│
             └────────────┘\
             """
  end
end
