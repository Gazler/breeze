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
    assert unfocused.style.background_color == 8
    assert focused.style.foreground_color == 7
    assert focused.style.background_color == 8
  end

  test "input semantic chooses sane defaults for system16" do
    placeholder =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: :system16, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: :system16)

    focused =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: :system16, focus: true)

    assert placeholder.style.background_color == 8
    assert placeholder.style.foreground_color == 7
    assert unfocused.style.background_color == 8
    assert unfocused.style.foreground_color == 15
    assert focused.style.background_color == 8
    assert focused.style.foreground_color == 15
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

    assert element.style.foreground_color ==
             Breeze.Theme.color(Breeze.Theme.system(palette: palette), :muted)

    assert element.style.background_color ==
             Breeze.Theme.color(Breeze.Theme.system(palette: palette), :panel)
  end

  test "input semantic keeps placeholder subtler than unfocused text on blendable themes" do
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
      |> Style.put_class("input")
      |> Style.to_element(theme: theme, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: theme)

    focused =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: theme, focus: true)

    assert placeholder.style.background_color == {51, 51, 51}
    assert placeholder.style.foreground_color == {122, 122, 122}
    assert unfocused.style.foreground_color == {153, 153, 153}
    assert focused.style.background_color == {63, 63, 63}
    assert focused.style.foreground_color == {238, 238, 238}
  end

  test "input semantic composes with placeholder tone on blendable themes" do
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
      |> Style.put_class("input placeholder:mute-40")
      |> Style.to_element(theme: theme, placeholder: true)

    value =
      Style.empty()
      |> Style.put_class("input placeholder:mute-40")
      |> Style.to_element(theme: theme)

    assert placeholder.style.foreground_color == {73, 73, 73}
    assert value.style.foreground_color == {153, 153, 153}
  end

  test "input semantic treats builtin solarized dark as a dark theme" do
    theme = Breeze.Theme.builtin(:solarized, :dark)

    placeholder =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: theme, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: theme)

    assert placeholder.style.foreground_color == {81, 98, 105}
    assert unfocused.style.foreground_color == {101, 123, 131}
  end

  test "input semantic overrides theme default foreground when defaults are enabled" do
    theme = Breeze.Theme.builtin(:solarized, :dark)

    placeholder =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: theme, apply_theme_defaults: true, placeholder: true)

    unfocused =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: theme, apply_theme_defaults: true)

    assert placeholder.style.foreground_color == {81, 98, 105}
    assert unfocused.style.foreground_color == {101, 123, 131}
  end

  test "input semantic lifts the background above panel on system themes" do
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
      |> Style.put_class("input")
      |> Style.to_element(theme: theme)

    focused =
      Style.empty()
      |> Style.put_class("input")
      |> Style.to_element(theme: theme, focus: true)

    assert unfocused.style.background_color == {44, 80, 88}
    assert focused.style.background_color != unfocused.style.background_color
    refute unfocused.style.background_color == Breeze.Theme.color(theme, :panel)
  end
end
