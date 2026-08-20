defmodule Breeze.ThemeTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers,
    only: [start_child_server: 1, stop_gen_server: 1]

  alias Breeze.Theme
  alias Breeze.Theme.Probe, as: ThemeProbe
  alias Breeze.Theme.Probe.TableOwner

  @text_colors [:text, :primary, :secondary, :warning, :error, :success, :accent]
  @surfaces [:background, :surface, :panel]

  defmodule PaletteAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts), do: {:ok, Map.new(opts)}
    def reader(term), do: {:ok, Map.fetch!(term, :ref)}
    def resize(_term), do: %{width: 80, height: 24}

    def write(term, _str) do
      ref = Map.fetch!(term, :ref)
      owner = self()

      send(owner, {ref, {:data, "\e]10;rgb:cdcd/d6d6/f4f4\a"}})
      send(owner, {ref, {:data, "\e]11;rgb:1818/1818/2525\a"}})
      send(owner, {ref, {:data, "\e]4;1;rgb:f28f/adad/adad\a"}})
      send(owner, {ref, {:data, "\e]4;2;rgb:abe9/b3b3/b3b3\a"}})
      send(owner, {ref, {:data, "\e]4;3;rgb:fae3/b0b0/b0b0\a"}})
      send(owner, {ref, {:data, "\e]4;4;rgb:f5f5/c2c2/e7e7\a"}})
      send(owner, {ref, {:data, "\e]4;5;rgb:fafa/b3b3/8787\a"}})
      send(owner, {ref, {:data, "\e]4;6;rgb:cba6/f7f7/f7f7\a"}})
      {:ok, term}
    end
  end

  defmodule ToggleView do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, term |> put_theme(Theme.system16()) |> assign(mode: :system16)}
    end

    def render(assigns) do
      ~H"""
      <box class="text-primary">Theme: {@mode}</box>
      """
    end

    def handle_event(_, %{"key" => "t"}, term) do
      theme =
        Theme.new(
          defaults: %{
            foreground_color: "#839496",
            background_color: "#002b36",
            border_color: "#586e75"
          },
          palette: %{primary: "#268bd2"}
        )

      {:noreply, term |> put_theme(theme) |> assign(mode: :custom)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  test "system16 uses ANSI slots" do
    theme = Theme.system16()

    assert Theme.color(theme, :primary) == 4
    assert Theme.color(theme, :background) == 0
    assert Theme.color(theme, :panel) == 0
    assert Theme.color(theme, :surface) == 8
    assert Theme.default_style(theme).border_color == 7
  end

  test "default_cycle lists the standard named themes" do
    assert Theme.default_cycle() == [
             :system16,
             :system,
             :greenscreen,
             :nebula,
             :catppuccin,
             :dracula,
             :commander,
             :gruvbox,
             :nord,
             :solarized_light,
             :solarized_dark
           ]
  end

  test "calculates WCAG contrast ratios for RGB and hexadecimal colors" do
    assert_in_delta Theme.contrast_ratio("#000000", "#ffffff"), 21.0, 0.001
    assert_in_delta Theme.contrast_ratio({119, 119, 119}, {255, 255, 255}), 4.478, 0.001
    assert Theme.contrast_ratio(0, 7) == nil
  end

  test "next_theme advances through a theme cycle" do
    assert {:commander, %Theme{name: "commander-blue"}} = Theme.next_theme(:dracula)
    assert {:nord, %Theme{name: "nord"}} = Theme.next_theme(:gruvbox)
    assert {:system16, :system16} = Theme.next_theme(:solarized_dark)
    assert {:system16, :system16} = Theme.next_theme(:missing)
    assert Theme.next_theme(:missing, []) == nil
  end

  test "system derives colors from the terminal palette" do
    theme =
      Theme.system(
        palette: %{
          1 => "#aa2233",
          2 => "#22aa33",
          3 => "#ccbb33",
          4 => "#3355aa",
          5 => "#9933aa",
          6 => "#33aaaa",
          7 => "#dddddd",
          8 => "#777777",
          background: "#101112",
          foreground: "#f0f0f0"
        }
      )

    assert Theme.color(theme, :background) == {16, 17, 18}
    assert Theme.color(theme, :primary) == {109, 149, 239}
    assert Theme.color(theme, :surface) == {34, 35, 36}
    assert Theme.color(theme, :panel) == {47, 48, 49}
  end

  test "system prefers base ANSI hues over bright grayscale slots for solarized-like palettes" do
    semantic_colors = %{
      primary: {38, 139, 210},
      secondary: {42, 161, 152},
      warning: {181, 137, 0},
      error: {220, 50, 47},
      success: {133, 153, 0},
      accent: {211, 54, 130}
    }

    theme =
      Theme.system(
        palette: %{
          1 => "#dc322f",
          2 => "#859900",
          3 => "#b58900",
          4 => "#268bd2",
          5 => "#d33682",
          6 => "#2aa198",
          9 => "#cb4b16",
          10 => "#586e75",
          11 => "#657b83",
          12 => "#839496",
          13 => "#6c71c4",
          14 => "#93a1a1",
          background: "#002b36",
          foreground: "#839496"
        }
      )

    assert elem(Theme.color(theme, :primary), 2) > elem(Theme.color(theme, :primary), 0)
    assert elem(Theme.color(theme, :secondary), 1) > elem(Theme.color(theme, :secondary), 0)
    assert elem(Theme.color(theme, :warning), 0) > elem(Theme.color(theme, :warning), 2)
    assert elem(Theme.color(theme, :error), 0) > elem(Theme.color(theme, :error), 1)
    assert elem(Theme.color(theme, :success), 1) > elem(Theme.color(theme, :success), 2)
    assert elem(Theme.color(theme, :accent), 0) > elem(Theme.color(theme, :accent), 1)

    refute Theme.color(theme, :primary) == {131, 148, 150}
    refute Theme.color(theme, :secondary) == {147, 161, 161}

    for {role, source} <- semantic_colors do
      corrected = Theme.color(theme, role)

      assert color_spread(corrected) >= color_spread(source) * 0.85,
             "system #{role} lost too much of the probed color's saturation"

      for background <- @surfaces do
        assert Theme.contrast_ratio(corrected, Theme.color(theme, background)) >= 4.5
      end
    end
  end

  test "system corrects low-contrast probed palettes for semantic use" do
    palettes = [
      %{background: "#202020", foreground: "#454545", ansi: "#303030"},
      %{background: "#f0f0f0", foreground: "#cccccc", ansi: "#dddddd"},
      %{background: "#3479e1", foreground: "#91303d", ansi: "#6778a0"}
    ]

    for palette <- palettes do
      terminal_palette =
        1..14
        |> Map.new(&{&1, palette.ansi})
        |> Map.merge(%{background: palette.background, foreground: palette.foreground})

      theme = Theme.system(palette: terminal_palette)

      for foreground <- @text_colors, background <- @surfaces do
        assert Theme.contrast_ratio(
                 Theme.color(theme, foreground),
                 Theme.color(theme, background)
               ) >= 4.5,
               "system #{foreground}/#{background} failed for #{inspect(palette)}"
      end

      for background <- @surfaces do
        assert Theme.contrast_ratio(
                 Theme.color(theme, :muted),
                 Theme.color(theme, background)
               ) >= 3.0
      end

      for background <- @surfaces do
        assert Theme.contrast_ratio(
                 Theme.color(theme, :border),
                 Theme.color(theme, background)
               ) >= 3.0
      end
    end
  end

  test "materialized system themes are reused until the terminal palette changes" do
    palette = %{
      1 => "#aa2233",
      2 => "#22aa33",
      3 => "#ccbb33",
      4 => "#3355aa",
      5 => "#9933aa",
      6 => "#33aaaa",
      background: "#101112",
      foreground: "#f0f0f0"
    }

    theme = Theme.system(palette: palette)

    refreshed = Theme.new(theme, palette: Map.put(palette, 4, "#4477dd"))
    refute Theme.color(theme, :primary) == Theme.color(refreshed, :primary)
  end

  test "system falls back to system16 when no runtime palette is available" do
    theme = Theme.system()

    assert theme.mode == :system16
    assert Theme.color(theme, :primary) == 4
    assert Theme.color(theme, :background) == 0
  end

  test "runtime palette query uses ST terminators instead of BEL" do
    ref = make_ref()

    terminal = %Termite.Terminal{
      reader: ref,
      adapter: {PaletteAdapter, %{ref: ref}},
      size: %{width: 80, height: 24}
    }

    assert {:start, {:reader, ^ref}, query} = ThemeProbe.start_runtime_palette_probe(terminal)
    refute query =~ "\a"
    assert query =~ "\e]10;?\e\\"
    assert query =~ "\e]4;6;?\e\\"
    refute query =~ "\e]4;9;?\e\\"
  end

  test "runtime palette tables have a stable owner" do
    ref = make_ref()

    terminal = %Termite.Terminal{
      reader: ref,
      adapter: {PaletteAdapter, %{ref: ref}},
      size: %{width: 80, height: 24}
    }

    assert {:start, {:reader, ^ref}, _query} = ThemeProbe.start_runtime_palette_probe(terminal)

    owner = Process.whereis(TableOwner)

    assert is_pid(owner)
    assert :ets.info(Breeze.Theme.Probe.PaletteCache, :owner) == owner
    assert :ets.info(Breeze.Theme.Probe.PaletteWaiters, :owner) == owner
  end

  test "system can derive colors from a probed runtime palette" do
    ref = make_ref()

    terminal = %Termite.Terminal{
      reader: ref,
      adapter: {PaletteAdapter, %{ref: ref}},
      size: %{width: 80, height: 24}
    }

    assert {:start, {:reader, ^ref}, query} = ThemeProbe.start_runtime_palette_probe(terminal)
    assert :ok = ThemeProbe.ensure_runtime_palette_async(terminal, self())
    _terminal = Termite.Terminal.write(terminal, query)

    palette = collect_probe_palette(%{})
    assert :ready = ThemeProbe.finish_runtime_palette_probe(terminal, palette)
    assert_receive {:breeze_theme_palette, {:reader, ^ref}, :ready}

    theme = Theme.new(:system, terminal: terminal)

    assert theme.mode == :system
    assert Theme.color(theme, :background) == {24, 24, 37}
    assert Theme.color(theme, :text) == {205, 214, 244}
    assert Theme.color(theme, :primary) == {245, 194, 231}
    assert Theme.color(theme, :accent) == {250, 179, 135}
    assert Theme.color(theme, :surface) == {38, 39, 54}
    assert Theme.color(theme, :panel) == {49, 51, 66}
  end

  test "partial probed palettes do not promote system mode" do
    ref = make_ref()

    terminal = %Termite.Terminal{
      reader: ref,
      adapter: {PaletteAdapter, %{ref: ref}},
      size: %{width: 80, height: 24}
    }

    partial = %{
      foreground: {205, 214, 244},
      background: {24, 24, 37}
    }

    assert :unavailable = ThemeProbe.finish_runtime_palette_probe(terminal, partial)
    assert Theme.new(:system, terminal: terminal).mode == :system16
  end

  test "system probe retries after an unavailable result" do
    ref = make_ref()

    terminal = %Termite.Terminal{
      reader: ref,
      adapter: {PaletteAdapter, %{ref: ref}},
      size: %{width: 80, height: 24}
    }

    partial = %{
      foreground: {205, 214, 244},
      background: {24, 24, 37}
    }

    assert :unavailable = ThemeProbe.finish_runtime_palette_probe(terminal, partial)
    assert {:start, {:reader, ^ref}, query} = ThemeProbe.start_runtime_palette_probe(terminal)

    assert :ok = ThemeProbe.ensure_runtime_palette_async(terminal, self())

    _terminal = Termite.Terminal.write(terminal, query)

    palette = collect_probe_palette(%{})
    assert :ready = ThemeProbe.finish_runtime_palette_probe(terminal, palette)
    assert_receive {:breeze_theme_palette, {:reader, ^ref}, :ready}
    assert Theme.new(:system, terminal: terminal).mode == :system
  end

  defp collect_probe_palette(palette, buffer \\ "")

  defp collect_probe_palette(palette, buffer) do
    receive do
      {_ref, {:data, data}} ->
        {palette, buffer} = ThemeProbe.merge_runtime_palette_data(buffer, palette, data)

        if ThemeProbe.runtime_palette_probe_complete?(palette) do
          palette
        else
          collect_probe_palette(palette, buffer)
        end
    after
      100 ->
        palette
    end
  end

  test "system keeps accessible RGB neutral tones where system16 uses ANSI fallbacks" do
    palette = %{
      1 => "#dc322f",
      2 => "#859900",
      3 => "#b58900",
      4 => "#268bd2",
      5 => "#d33682",
      6 => "#2aa198",
      9 => "#cb4b16",
      10 => "#586e75",
      11 => "#657b83",
      12 => "#839496",
      13 => "#6c71c4",
      14 => "#93a1a1",
      background: "#002b36",
      foreground: "#839496"
    }

    system = Theme.system(palette: palette)
    system16 = Theme.system16(palette: palette)

    assert Theme.color(system16, :primary) == 4
    assert Theme.color(system16, :panel) == 0
    assert Theme.color(system16, :surface) == 8
    assert Theme.color(system, :panel) == {18, 58, 67}
    assert Theme.color(system, :surface) == {10, 51, 62}
    refute Theme.color(system16, :muted) == Theme.color(system, :muted)

    muted_contrast =
      Theme.contrast_ratio(Theme.color(system, :muted), Theme.color(system, :panel))

    text_contrast =
      Theme.contrast_ratio(Theme.color(system, :text), Theme.color(system, :panel))

    assert muted_contrast >= 3.0
    assert muted_contrast < text_contrast
  end

  test "custom themes preserve explicit colors" do
    theme =
      Theme.new(
        defaults: %{
          foreground_color: "#D6E7FF",
          background_color: "#0D2137",
          border_color: "#4A9CFF"
        },
        palette: %{primary: "#4A9CFF"}
      )

    assert Theme.color(theme, :primary) == {74, 156, 255}
    assert Theme.color(theme, :background) == {13, 33, 55}
  end

  test "resolves known string keys and atom-keyed extras without creating atoms" do
    unknown_key = "unknown-theme-key-#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown_key) end

    theme =
      Theme.new(
        defaults: %{"foreground-color" => "#D6E7FF"},
        palette: %{"primary" => "#4A9CFF"},
        extras: %{unknown_key => "#FFFFFF", brand: "#9B8AFB"}
      )

    assert Theme.color(theme, "foreground-color") == {214, 231, 255}
    assert Theme.color(theme, "primary") == {74, 156, 255}
    assert Theme.color(theme, "brand") == {155, 138, 251}
    assert Theme.color(theme, unknown_key) == nil
    refute Map.has_key?(theme.extras, nil)
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown_key) end
  end

  test "resolves renderable class colors and ignores unmatched values" do
    theme = Theme.new(extras: %{brand: "#9B8AFB"})

    assert Theme.resolve_class_color(theme, "brand") == {155, 138, 251}
    assert Theme.resolve_class_color(theme, "255") == 255

    assert Theme.resolve_class_color(theme, "lol") == nil
    assert Theme.resolve_class_color(theme, "256") == nil
    assert Theme.resolve_class_color(theme, "#abc") == nil
    assert Theme.resolve_class_color(theme, "#xyz") == nil
  end

  test "nebula uses a quieter default border than its focus color" do
    theme = Theme.builtin(:nebula)

    assert Theme.default_style(theme).border_color == {47, 111, 153}
    assert Theme.color(theme, :primary) == {74, 156, 255}
    refute Theme.default_style(theme).border_color == Theme.color(theme, :primary)
  end

  test "builtin themes can be loaded by name and variant" do
    light = Theme.builtin(:solarized, :light)
    dark = Theme.builtin(:solarized, :dark)

    assert light.name == "solarized-light"
    assert dark.name == "solarized-dark"
    assert Theme.color(dark, :background) == {0, 43, 54}
    assert Theme.color(dark, :panel) == {4, 38, 45}
    assert Theme.color(dark, :cursor) == {131, 148, 150}
  end

  test "built-in constructors stay behind the Theme.builtin API" do
    for constructor <-
          ~w(greenscreen nebula catppuccin dracula commander gruvbox nord solarized_light solarized_dark)a do
      refute function_exported?(Breeze.Theme.Builtin, constructor, 0)
    end
  end

  test "greenscreen builtin theme uses only green and black without color blending" do
    theme = Theme.builtin(:greenscreen)

    assert theme.name == "greenscreen"
    assert theme.dark == true
    refute Theme.color_blending?(theme)
    refute Theme.blendable?(theme)

    assert Theme.color(theme, :text) == {0, 255, 0}
    assert Theme.color(theme, :background) == {0, 0, 0}
    assert Theme.color(theme, :border) == {0, 255, 0}
    assert Theme.color(theme, :surface) == {0, 0, 0}
    assert Theme.color(theme, :panel) == {0, 0, 0}

    colors =
      theme.defaults
      |> Map.values()
      |> Kernel.++(Map.values(theme.palette))
      |> Kernel.++(Map.values(theme.extras))
      |> MapSet.new()

    assert colors == MapSet.new([{0, 0, 0}, {0, 255, 0}])
  end

  test "commander builtin theme matches classic blue TUI colors" do
    theme = Theme.builtin(:commander)

    assert theme.name == "commander-blue"
    assert theme.dark == true
    assert Theme.color(theme, :text) == {255, 255, 255}
    assert Theme.color(theme, :background) == {0, 0, 0}
    assert Theme.color(theme, :border) == {0, 170, 170}
    assert Theme.color(theme, :panel) == {0, 0, 170}
    assert Theme.color(theme, :surface) == {0, 0, 119}
    assert Theme.color(theme, :primary) == {0, 255, 255}
    refute Theme.color(theme, :border) == Theme.color(theme, :primary)
    assert Theme.color(theme, :cursor) == {255, 255, 85}
    assert Theme.builtin(:commander, :blue).name == "commander-blue"
  end

  test "views can switch themes at runtime" do
    session = Breeze.Test.start!(ToggleView)
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "\e[38;5;4mTheme: system16\e[0m"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "t")
    assert Breeze.Test.render!(session) =~ "\e[38;2;38;139;210mTheme: custom\e[0m"
  end

  test "child metadata reflects theme changes" do
    {:ok, pid} = start_child_server(view: ToggleView, start_opts: [])
    on_exit(fn -> stop_gen_server(pid) end)

    assert Breeze.ChildServer.metadata(pid).theme.mode == :system16
    assert {:noreply, _focused, true} = Breeze.ChildServer.dispatch_input(pid, "t")
    assert Breeze.ChildServer.metadata(pid).theme.mode == :custom
  end

  defp color_spread(color) do
    channels = Tuple.to_list(color)
    Enum.max(channels) - Enum.min(channels)
  end
end
