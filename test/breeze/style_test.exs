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

  test "ignores string keys in inline style maps without creating atoms" do
    unknown_key = "unknown-style-#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown_key) end

    element =
      Style.empty()
      |> Style.put_style(%{"bold" => true, unknown_key => true})
      |> Style.to_element([])

    refute element.style.bold
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown_key) end
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

  test "normalizes invalid inline border values" do
    element =
      Style.empty()
      |> Style.put_style(%{border: {50, 48, 47}})
      |> Style.to_element([])

    assert element.style.border == BackBreeze.Border.none()
  end

  test "supports conditional class maps" do
    element =
      Style.empty()
      |> Style.put_class(%{"bold" => true, "text-2" => true, "hidden" => false})
      |> Style.to_element([])

    assert element.style.bold
    assert element.style.foreground_color == 2
  end

  test "supports hidden class" do
    element =
      Style.empty()
      |> Style.put_class("hidden")
      |> Style.to_element([])

    assert element.style.width == 0
    assert element.style.height == 0
    assert element.style.overflow == :hidden
  end

  test "supports border-invisible class" do
    element =
      Style.empty()
      |> Style.put_class("border-invisible")
      |> Style.to_element([])

    assert element.style.border == BackBreeze.Border.invisible()
    assert element.style.border.left == " "
    assert element.style.border.top == " "
  end

  test "supports border-none class" do
    element =
      Style.empty()
      |> Style.put_class("border border-none")
      |> Style.to_element([])

    assert element.style.border == BackBreeze.Border.none()
  end

  test "supports border-square class" do
    element =
      Style.empty()
      |> Style.put_class("border-square")
      |> Style.to_element([])

    assert element.style.border.style == :custom
    assert element.style.border.top == "▁"
    assert element.style.border.bottom == "▔"
    assert element.style.border.left == "▌"
    assert element.style.border.right == "▐"
    assert element.style.border.top_left == "▁"
    assert element.style.border.bottom_right == "▔"
  end

  test "resolve_dimensions reads width and height from classes" do
    assert Style.resolve_dimensions("width-12 height-4", nil) == %{width: 12, height: 4}
  end

  test "resolve_dimensions treats binary style as class tokens" do
    assert Style.resolve_dimensions(nil, "width-10 height-3") == %{width: 10, height: 3}
  end

  test "resolve_dimensions lets inline style override class dimensions" do
    assert Style.resolve_dimensions("width-12 height-4", %{width: 8, height: :full}) == %{
             width: 8,
             height: :full
           }
  end

  test "scrollbars default to the resolved foreground color" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#111111",
          border_color: "#666666"
        },
        palette: %{primary: "#268bd2"}
      )

    element =
      Style.empty()
      |> Style.put_class("text overflow-scroll scrollbar-arrows")
      |> Style.to_element(theme: theme)

    assert element.style.scrollbar.vertical.thumb.foreground_color == {238, 238, 238}
    assert element.style.scrollbar.vertical.track.foreground_color == {238, 238, 238}
  end

  test "semantic scrollbar colors apply only when their modifier matches" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#111111",
          border_color: "#666666"
        },
        palette: %{primary: "#268bd2"}
      )

    unfocused =
      Style.empty()
      |> Style.put_class("text overflow-scroll scrollbar-arrows focus:scrollbar-primary")
      |> Style.to_element(theme: theme)

    focused =
      Style.empty()
      |> Style.put_class("text overflow-scroll scrollbar-arrows focus:scrollbar-primary")
      |> Style.to_element(theme: theme, focus: true)

    assert unfocused.style.scrollbar.vertical.thumb.foreground_color == {238, 238, 238}
    assert focused.style.scrollbar.vertical.thumb.foreground_color == {38, 139, 210}
  end

  test "mute-scrollbar tones the scrollbar foreground toward the theme background" do
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
      |> Style.put_class("text overflow-scroll scrollbar-arrows mute-scrollbar-20")
      |> Style.to_element(theme: theme)

    expected =
      Breeze.Theme.blend(
        {238, 238, 238},
        {17, 17, 17},
        0.20
      )

    assert element.style.scrollbar.vertical.thumb.foreground_color == expected
    assert element.style.scrollbar.vertical.track.foreground_color == expected
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

  test "lighten tokens lighten text and background by the requested percentage" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#000000",
          border_color: "#666666"
        },
        palette: %{panel: "#808080"},
        extras: %{}
      )

    element =
      Style.empty()
      |> Style.put_class("text bg-panel border border-stroke lighten-50")
      |> Style.to_element(theme: theme)

    assert element.style.foreground_color == {247, 247, 247}
    assert element.style.background_color == {192, 192, 192}
    assert element.style.border_color == {102, 102, 102}
  end

  test "focus modifiers can override lighten tokens and synthesize a default background tint" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#000000",
          border_color: "#666666"
        },
        palette: %{panel: "#808080"},
        extras: %{}
      )

    unfocused =
      Style.empty()
      |> Style.put_class("text lighten-30 focus:lighten-0")
      |> Style.to_element(theme: theme)

    focused =
      Style.empty()
      |> Style.put_class("text lighten-30 focus:lighten-0")
      |> Style.to_element(theme: theme, focus: true)

    assert unfocused.style.background_color == {166, 166, 166}
    assert focused.style.background_color == {128, 128, 128}
    assert unfocused.style.foreground_color == {243, 243, 243}
    assert focused.style.foreground_color == {238, 238, 238}
  end

  test "lighten tokens do not blend colors for system themes" do
    unfocused =
      Style.empty()
      |> Style.put_class("text lighten-30 focus:lighten-0")
      |> Style.to_element(theme: :system)

    focused =
      Style.empty()
      |> Style.put_class("text lighten-30 focus:lighten-0")
      |> Style.to_element(theme: :system, focus: true)

    assert unfocused.style.background_color == nil
    assert focused.style.background_color == nil
    assert unfocused.style.foreground_color == 7
    assert focused.style.foreground_color == 7
  end

  test "system16 ignores semantic tone transforms" do
    unfocused =
      Style.empty()
      |> Style.put_class(
        "bg-panel text-muted focus:text focus:bg-emphasize-10 placeholder:mute-40"
      )
      |> Style.to_element(theme: :system16, placeholder: true)

    focused =
      Style.empty()
      |> Style.put_class(
        "bg-panel text-muted focus:text focus:bg-emphasize-10 placeholder:mute-40"
      )
      |> Style.to_element(theme: :system16, focus: true, placeholder: true)

    assert unfocused.style.foreground_color == 7
    assert unfocused.style.background_color == 0
    assert focused.style.foreground_color == 7
    assert focused.style.background_color == 0
  end

  test "explicit input semantic classes choose sane defaults for system16" do
    placeholder =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: :system16, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: :system16)

    focused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: :system16, focus: true)

    assert placeholder.style.background_color == nil
    assert placeholder.style.foreground_color == 7
    assert unfocused.style.background_color == nil
    assert unfocused.style.foreground_color == 7
    assert focused.style.background_color == nil
    assert focused.style.foreground_color == 7
  end

  test "placeholder modifiers only affect placeholder text" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#808080",
          background_color: "#000000",
          border_color: "#666666"
        },
        palette: %{},
        extras: %{}
      )

    placeholder =
      Style.empty()
      |> Style.put_class("text placeholder:lighten-30")
      |> Style.to_element(theme: theme, placeholder: true)

    normal =
      Style.empty()
      |> Style.put_class("text placeholder:lighten-30")
      |> Style.to_element(theme: theme)

    assert placeholder.style.foreground_color == {166, 166, 166}
    assert normal.style.foreground_color == {128, 128, 128}
  end

  test "placeholder tone overrides focused text color" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#808080",
          background_color: "#000000",
          border_color: "#666666"
        },
        dark: true,
        palette: %{},
        extras: %{}
      )

    focused_placeholder =
      Style.empty()
      |> Style.put_class("text-muted focus:text placeholder:mute-40")
      |> Style.to_element(theme: theme, focus: true, placeholder: true)

    focused_value =
      Style.empty()
      |> Style.put_class("text-muted focus:text placeholder:mute-40")
      |> Style.to_element(theme: theme, focus: true)

    assert focused_placeholder.style.foreground_color == {77, 77, 77}
    assert focused_value.style.foreground_color == {128, 128, 128}
  end

  test "placeholder mute composes with focused background emphasis on blendable themes" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#808080",
          background_color: "#000000",
          border_color: "#666666"
        },
        dark: true,
        palette: %{panel: "#808080"},
        extras: %{}
      )

    element =
      Style.empty()
      |> Style.put_class("bg-panel text focus:bg-emphasize-10 placeholder:mute-40")
      |> Style.to_element(theme: theme, focus: true, placeholder: true)

    assert element.style.foreground_color == {77, 77, 77}
    assert element.style.background_color == {141, 141, 141}
  end

  test "mute semantics swap direction for dark and light themes" do
    dark_theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#808080",
          background_color: "#000000",
          border_color: "#666666"
        },
        dark: true,
        palette: %{},
        extras: %{}
      )

    light_theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#808080",
          background_color: "#ffffff",
          border_color: "#666666"
        },
        dark: false,
        palette: %{},
        extras: %{}
      )

    dark =
      Style.empty()
      |> Style.put_class("text mute-40")
      |> Style.to_element(theme: dark_theme)

    light =
      Style.empty()
      |> Style.put_class("text mute-40")
      |> Style.to_element(theme: light_theme)

    assert dark.style.foreground_color == {77, 77, 77}
    assert light.style.foreground_color == {179, 179, 179}
  end

  test "bg-emphasize only changes the background color" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#808080",
          background_color: "#000000",
          border_color: "#666666"
        },
        dark: true,
        palette: %{panel: "#808080"},
        extras: %{}
      )

    element =
      Style.empty()
      |> Style.put_class("bg-panel text bg-emphasize-10")
      |> Style.to_element(theme: theme)

    assert element.style.background_color == {141, 141, 141}
    assert element.style.foreground_color == {128, 128, 128}
  end

  test "system fallback composes placeholder mute with focused background emphasis" do
    palette = %{
      0 => "#101112",
      7 => "#f0f0f0",
      8 => "#777777",
      background: "#101112",
      foreground: "#f0f0f0"
    }

    element =
      Style.empty()
      |> Style.put_class("bg-panel text focus:bg-emphasize-10 placeholder:mute-40")
      |> Style.to_element(
        theme: Breeze.Theme.system(palette: palette),
        focus: true,
        placeholder: true
      )

    assert element.style.foreground_color == {150, 151, 151}
    assert element.style.background_color == {66, 67, 68}
  end

  test "explicit input semantic classes keep placeholder subtler than unfocused text on blendable themes" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#111111",
          border_color: "#666666"
        },
        dark: true,
        palette: %{muted: "#999999", panel: "#333333"},
        extras: %{}
      )

    placeholder =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme)

    focused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme, focus: true)

    assert placeholder.style.background_color == {112, 112, 112}
    assert placeholder.style.foreground_color == {137, 137, 137}
    assert unfocused.style.foreground_color == {171, 171, 171}
    assert focused.style.background_color == {139, 139, 139}
    assert focused.style.foreground_color == {238, 238, 238}
  end

  test "explicit input semantic classes compose with placeholder tone on blendable themes" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#111111",
          border_color: "#666666"
        },
        dark: true,
        palette: %{muted: "#999999", panel: "#333333"},
        extras: %{}
      )

    placeholder =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20 placeholder:mute-40"
      )
      |> Style.to_element(theme: theme, placeholder: true)

    value =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20 placeholder:mute-40"
      )
      |> Style.to_element(theme: theme)

    assert placeholder.style.foreground_color == {103, 103, 103}
    assert value.style.foreground_color == {171, 171, 171}
  end

  test "explicit input semantic classes treat builtin solarized dark as a dark theme" do
    theme = Breeze.Theme.builtin(:solarized, :dark)

    placeholder =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme)

    assert placeholder.style.foreground_color == {75, 86, 86}
    assert unfocused.style.foreground_color == {94, 107, 108}
  end

  test "explicit input semantic classes override theme default foreground when defaults are enabled" do
    theme = Breeze.Theme.builtin(:solarized, :dark)

    placeholder =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme, apply_theme_defaults: true, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme, apply_theme_defaults: true)

    assert placeholder.style.foreground_color == {75, 86, 86}
    assert unfocused.style.foreground_color == {94, 107, 108}
  end

  test "explicit input semantic classes preserve system theme input contrast" do
    theme =
      Breeze.Theme.system(
        palette: %{
          0 => "#002b36",
          7 => "#93a1a1",
          8 => "#657b83",
          background: "#002b36",
          foreground: "#93a1a1"
        }
      )

    unfocused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme)

    focused =
      Style.empty()
      |> Style.put_class(
        "input text mute-text-28 bg-emphasize-30 focus:text focus:mute-text-0 focus:emphasize-bg-43 placeholder:mute-text-20"
      )
      |> Style.to_element(theme: theme, focus: true)

    assert unfocused.style.foreground_color == {106, 128, 131}
    assert focused.style.foreground_color == {147, 161, 161}
    assert unfocused.style.background_color == {44, 78, 86}
    assert focused.style.background_color == {63, 94, 100}
  end
end
