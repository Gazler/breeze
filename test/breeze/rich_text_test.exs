defmodule Breeze.RichTextTest do
  use ExUnit.Case, async: true

  alias BackBreeze.TextSpan

  test "renders styled text spans within a box" do
    content = [
      TextSpan.new("Hello ", %{foreground_color: 2}),
      TextSpan.new("World", %{bold: true, foreground_color: 4})
    ]

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(13)

    output = BackBreeze.Style.render(style, content)

    assert output ==
             """
             ┌───────────┐
             │\e[38;5;2mHello \e[0m\e[1;38;5;4mWorld\e[0m│
             └───────────┘\
             """
  end

  test "wraps text spans by viewport width" do
    content = [
      TextSpan.new("Hello ", %{foreground_color: 2}),
      TextSpan.new("Wide", %{foreground_color: 4}),
      TextSpan.new(" World", %{bold: true})
    ]

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(8)
      |> BackBreeze.Style.height(4)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content)

    assert output ==
             """
             ┌──────┐
             │\e[38;5;2mHello \e[0m│
             │\e[38;5;4mWide\e[0m\e[1m W\e[0m│
             └──────┘\
             """
  end

  test "supports deep viewport slicing for text spans" do
    content =
      1..200
      |> Enum.map(fn index ->
        [
          TextSpan.new("Line ", %{foreground_color: 2}),
          TextSpan.new(Integer.to_string(index), %{bold: true})
        ]
      end)
      |> Enum.intersperse([TextSpan.new("\n")])
      |> List.flatten()

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(10)
      |> BackBreeze.Style.height(4)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content, offset_top: 197)

    assert output ==
             """
             ┌────────┐
             │\e[38;5;2mLine \e[0m\e[1m198\e[0m│
             │\e[38;5;2mLine \e[0m\e[1m199\e[0m│
             └────────┘\
             """
  end
end
