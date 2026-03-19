defmodule Breeze.StyleTest do
  use ExUnit.Case, async: true

  alias Breeze.Style

  test "coerces binary style values onto the class pipeline" do
    element =
      Style.empty()
      |> Style.put_style("text-3 bold")
      |> Style.to_element([])

    assert element.style.foreground_color == 3
    assert element.style.bold
  end

  test "merges inline maps after class tokens" do
    element =
      Style.empty()
      |> Style.put_class("text-3")
      |> Style.put_style(%{foreground_color: 5, background_color: 0})
      |> Style.to_element([])

    assert element.style.foreground_color == 5
    assert element.style.background_color == 0
  end

  test "accepts BackBreeze.Style structs as inline styles" do
    inline_style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.border_color(4)
      |> BackBreeze.Style.width(12)

    element =
      Style.empty()
      |> Style.put_style(inline_style)
      |> Style.to_element([])

    assert element.style.border_color == 4
    assert element.style.width == 12
    assert element.style.border.left == "│"
  end

  test "supports conditional class maps" do
    element =
      Style.empty()
      |> Style.put_class(%{"bold" => true, "text-2" => true, "hidden" => false})
      |> Style.to_element([])

    assert element.style.bold
    assert element.style.foreground_color == 2
  end

  test "supports semantic aliases for default text, background, and border colors" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#111111",
          border_color: "#666666"
        }
      )

    element =
      Style.empty()
      |> Style.put_class("text bg border border-stroke")
      |> Style.to_element(theme: theme)

    assert element.style.foreground_color == {238, 238, 238}
    assert element.style.background_color == {17, 17, 17}
    assert element.style.border_color == {102, 102, 102}
  end
end
