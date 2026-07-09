defmodule Breeze.ThemeTest do
  use ExUnit.Case, async: true

  alias Breeze.Theme

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
      send(owner, {ref, {:data, "\e]4;9;rgb:f28f/adad/adad\a"}})
      send(owner, {ref, {:data, "\e]4;10;rgb:abe9/b3b3/b3b3\a"}})
      send(owner, {ref, {:data, "\e]4;11;rgb:fae3/b0b0/b0b0\a"}})
      send(owner, {ref, {:data, "\e]4;12;rgb:f5f5/c2c2/e7e7\a"}})
      send(owner, {ref, {:data, "\e]4;13;rgb:fafa/b3b3/8787\a"}})
      send(owner, {ref, {:data, "\e]4;14;rgb:cba6/f7f7/f7f7\a"}})
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
             :nebula,
             :catppuccin,
             :dracula,
             :gruvbox,
             :nord,
             :solarized_light,
             :solarized_dark
           ]
  end

  test "resolve_theme resolves special and built-in named themes" do
    assert Theme.resolve_theme(:system16) == {:system16, :system16}
    assert Theme.resolve_theme(:system) == {:system, :system}
    assert {:gruvbox, %Theme{name: "gruvbox-dark"}} = Theme.resolve_theme(:gruvbox)
  end

  test "next_theme advances through a theme cycle" do
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
    assert Theme.color(theme, :primary) == {51, 85, 170}
    assert Theme.color(theme, :surface) == {34, 35, 36}
    assert Theme.color(theme, :panel) == {47, 48, 49}
  end

  test "system prefers base ANSI hues over bright grayscale slots for solarized-like palettes" do
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

    assert Theme.color(theme, :primary) == {38, 139, 210}
    assert Theme.color(theme, :secondary) == {42, 161, 152}
    assert Theme.color(theme, :warning) == {181, 137, 0}
    assert Theme.color(theme, :error) == {220, 50, 47}
    assert Theme.color(theme, :success) == {133, 153, 0}
    assert Theme.color(theme, :accent) == {211, 54, 130}
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

    assert {:start, {:reader, ^ref}, query} = Theme.start_runtime_palette_probe(terminal)
    refute query =~ "\a"
    assert query =~ "\e]10;?\e\\"
    assert query =~ "\e]4;14;?\e\\"
  end

  test "system can derive colors from a probed runtime palette" do
    ref = make_ref()

    terminal = %Termite.Terminal{
      reader: ref,
      adapter: {PaletteAdapter, %{ref: ref}},
      size: %{width: 80, height: 24}
    }

    assert {:start, {:reader, ^ref}, query} = Theme.start_runtime_palette_probe(terminal)
    assert :ok = Theme.ensure_runtime_palette_async(terminal, self())
    _terminal = Termite.Terminal.write(terminal, query)

    palette = collect_probe_palette(%{})
    assert :ready = Theme.finish_runtime_palette_probe(terminal, palette)
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

    assert :unavailable = Theme.finish_runtime_palette_probe(terminal, partial)
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

    assert :unavailable = Theme.finish_runtime_palette_probe(terminal, partial)
    assert {:start, {:reader, ^ref}, query} = Theme.start_runtime_palette_probe(terminal)

    assert :ok = Theme.ensure_runtime_palette_async(terminal, self())

    _terminal = Termite.Terminal.write(terminal, query)

    palette = collect_probe_palette(%{})
    assert :ready = Theme.finish_runtime_palette_probe(terminal, palette)
    assert_receive {:breeze_theme_palette, {:reader, ^ref}, :ready}
    assert Theme.new(:system, terminal: terminal).mode == :system
  end

  defp collect_probe_palette(palette, buffer \\ "")

  defp collect_probe_palette(palette, buffer) do
    receive do
      {_ref, {:data, data}} ->
        {palette, buffer} = Theme.merge_runtime_palette_data(buffer, palette, data)

        if Theme.runtime_palette_probe_complete?(palette) do
          palette
        else
          collect_probe_palette(palette, buffer)
        end
    after
      100 ->
        palette
    end
  end

  test "system keeps derived RGB neutral tones where system16 falls back on solarized-like palettes" do
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
    assert Theme.color(system16, :muted) == Theme.color(system, :muted)
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

  test "views can switch themes at runtime" do
    session = Breeze.Test.start!(ToggleView)
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "\e[38;5;4mTheme: system16\e[0m"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "t")
    assert Breeze.Test.render!(session) =~ "\e[38;2;38;139;210mTheme: custom\e[0m"
  end

  test "child metadata reflects theme changes" do
    {:ok, pid} = Breeze.ChildServer.start(view: ToggleView, start_opts: [])
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

    assert Breeze.ChildServer.metadata(pid).theme.mode == :system16
    assert {:noreply, _focused, true} = Breeze.ChildServer.dispatch_input(pid, "t")
    assert Breeze.ChildServer.metadata(pid).theme.mode == :custom
  end
end
