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

  test "ignores class colors that the active theme cannot resolve" do
    element =
      Style.empty()
      |> Style.put_class(
        "text-3 text-lol text-#abc bg-4 bg-lol bg-#abc border border-5 border-lol " <>
          "border-#abc overflow-scroll scrollbar-lol scrollbar-#abc"
      )
      |> Style.to_element([])

    assert element.style.foreground_color == 3
    assert element.style.background_color == 4
    assert element.style.border == BackBreeze.Border.line()
    assert element.style.border_color == 5
    refute element.attributes[:scrollbar_color_explicit]
  end

  test "raw hex colors remain available through inline styles" do
    element =
      Style.empty()
      |> Style.put_style(%{
        foreground_color: "#abc",
        background_color: "#123456",
        border_color: "#def"
      })
      |> Style.to_element([])

    assert element.style.foreground_color == "#abc"
    assert element.style.background_color == "#123456"
    assert element.style.border_color == "#def"
  end

  test "class colors resolve custom theme extras" do
    theme =
      Breeze.Theme.new(
        defaults: %{
          foreground_color: "#eeeeee",
          background_color: "#111111",
          border_color: "#666666"
        },
        extras: %{brand: "#9B8AFB"}
      )

    element =
      Style.empty()
      |> Style.put_class("text-brand bg-brand border border-brand")
      |> Style.to_element(theme: theme)

    assert element.style.foreground_color == {155, 138, 251}
    assert element.style.background_color == {155, 138, 251}
    assert element.style.border_color == {155, 138, 251}
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

  test "supports max-height classes, aliases, and inline styles" do
    class_element =
      Style.empty()
      |> Style.put_class("height-full max-height-23")
      |> Style.to_element([])

    alias_element =
      Style.empty()
      |> Style.put_class("h-full max-h-19")
      |> Style.to_element([])

    inline_element =
      Style.empty()
      |> Style.put_style(%{max_height: 17})
      |> Style.to_element([])

    assert class_element.style.height == :full
    assert class_element.style.max_height == 23
    assert alias_element.style.height == :full
    assert alias_element.style.max_height == 19
    assert inline_element.style.max_height == 17
  end

  describe "Tailwind-compatible utilities" do
    test "supports width, height, and size utilities" do
      assert Style.resolve_dimensions("w-12 h-4") == %{width: 12, height: 4}
      assert Style.resolve_dimensions("w-full h-screen") == %{width: :full, height: :screen}
      assert Style.resolve_dimensions("size-6") == %{width: 6, height: 6}
    end

    test "supports padding utilities, including axis shorthands" do
      element =
        Style.empty()
        |> Style.put_class("p-1 px-2 py-3 pl-4")
        |> Style.to_element([])

      assert element.style.padding == 1
      assert element.style.padding_top == 3
      assert element.style.padding_right == 2
      assert element.style.padding_bottom == 3
      assert element.style.padding_left == 4
    end

    test "supports typography, border radius, layer, and gap utilities" do
      element =
        Style.empty()
        |> Style.put_class("grid gap-1 gap-x-2 gap-y-3 rounded font-bold italic z-10")
        |> Style.to_element([])

      assert element.style.bold
      assert element.style.italic
      assert element.style.border == BackBreeze.Border.rounded()
      assert element.attributes.layer == 10
      assert element.attributes.display.gap_x == 2
      assert element.attributes.display.gap_y == 3
    end

    test "supports individual border side utilities" do
      element =
        Style.empty()
        |> Style.put_class("border-t border-r border-b border-l")
        |> Style.to_element([])

      assert element.style.border == BackBreeze.Border.line()
    end

    test "supports Tailwind reset utilities" do
      element =
        Style.empty()
        |> Style.put_class("font-bold italic font-normal not-italic")
        |> Style.to_element([])

      refute element.style.bold
      refute element.style.italic
    end

    test "supports Tailwind utilities behind responsive and state modifiers" do
      narrow = responsive_element("w-10 md:w-full focus:font-bold", {59, 24}, focus: true)
      wide = responsive_element("w-10 md:w-full focus:font-bold", {60, 24}, focus: true)

      assert narrow.style.width == 10
      assert wide.style.width == :full
      assert narrow.style.bold
      assert wide.style.bold
    end

    test "ignores unsupported Tailwind values" do
      element =
        Style.empty()
        |> Style.put_class(
          "w-fit h-min p-auto z-auto gap-auto w-px h-px size-px p-px px-px py-px pt-px pr-px pb-px pl-px gap-px inset-px"
        )
        |> Style.to_element([])

      assert element.style.width == :auto
      assert element.style.height == 0
      assert element.style.padding == 0
      refute Map.has_key?(element.attributes, :layer)
    end
  end

  describe "responsive modifiers" do
    test "applies width breakpoints at their minimum width" do
      class =
        "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6"

      assert grid_columns(class, {39, 24}) == 1
      assert grid_columns(class, {40, 24}) == 2
      assert grid_columns(class, {60, 24}) == 3
      assert grid_columns(class, {80, 24}) == 4
      assert grid_columns(class, {120, 24}) == 5
      assert grid_columns(class, {160, 24}) == 6
    end

    test "supports chained responsive and state modifiers" do
      class = "text-1 md:focus:text-2 focus:md:bold"

      narrow = responsive_element(class, {59, 24}, focus: true)
      wide_unfocused = responsive_element(class, {60, 24})
      wide_focused = responsive_element(class, {60, 24}, focus: true)

      assert narrow.style.foreground_color == 1
      refute narrow.style.bold
      assert wide_unfocused.style.foreground_color == 1
      refute wide_unfocused.style.bold
      assert wide_focused.style.foreground_color == 2
      assert wide_focused.style.bold
    end

    test "display utilities reveal a responsively hidden box" do
      narrow = responsive_element("hidden md:block", {59, 24})
      wide = responsive_element("hidden md:block", {60, 24})

      assert narrow.style.width == 0
      assert narrow.style.height == 0
      assert narrow.style.overflow == :hidden

      assert wide.attributes.display == :block
      assert wide.style.width == :auto
      assert wide.style.height == :auto
      assert wide.style.overflow == :auto
    end

    test "hidden suppresses decorative styles until a display utility reveals them" do
      class = "hidden md:block border-rounded padding-2 bg-primary"
      narrow = responsive_element(class, {59, 24})
      wide = responsive_element(class, {60, 24})

      assert narrow.style.border == BackBreeze.Border.none()
      assert narrow.style.padding == 0
      assert narrow.style.background_color == nil

      assert wide.style.border == BackBreeze.Border.rounded()
      assert wide.style.padding == 2
      assert wide.style.background_color == 4
    end

    test "does not apply responsive modifiers without terminal dimensions" do
      element =
        Style.empty()
        |> Style.put_class("text-1 sm:text-2 sm:bold")
        |> Style.to_element([])

      assert element.style.foreground_color == 1
      refute element.style.bold
    end
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

  defp grid_columns(class, size) do
    class
    |> responsive_element(size)
    |> then(& &1.attributes.display.columns)
  end

  defp responsive_element(class, {width, height}, opts \\ []) do
    terminal = %Termite.Terminal{size: %{width: width, height: height}}

    Style.empty()
    |> Style.put_class(class)
    |> Style.to_element(Keyword.put(opts, :terminal, terminal))
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

  test "theme default backgrounds propagate to scrollbar segments" do
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
      |> Style.put_class("border overflow-scroll scrollbar-arrows")
      |> Style.to_element(theme: theme, apply_theme_defaults: true)

    assert element.style.background_color == {17, 17, 17}
    assert element.style.scrollbar.vertical.thumb.background_color == {17, 17, 17}
    assert element.style.scrollbar.vertical.track.background_color == {17, 17, 17}
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

  test "greenscreen theme ignores tone and scrollbar color blending" do
    theme = Breeze.Theme.builtin(:greenscreen)

    element =
      Style.empty()
      |> Style.put_class(
        "bg-panel text-muted border-error overflow-scroll scrollbar-arrows lighten-20 darken-20 mute-40 text-emphasize-30 bg-emphasize-20 mute-scrollbar-20 placeholder:mute-40"
      )
      |> Style.to_element(theme: theme, placeholder: true)

    assert element.style.foreground_color == {0, 255, 0}
    assert element.style.background_color == {0, 0, 0}
    assert element.style.border_color == {0, 255, 0}
    assert element.style.scrollbar.vertical.thumb.foreground_color == {0, 255, 0}
    assert element.style.scrollbar.vertical.track.foreground_color == {0, 255, 0}
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
