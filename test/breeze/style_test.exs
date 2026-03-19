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
end
