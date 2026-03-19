defmodule Breeze.ThemeTest do
  use ExUnit.Case, async: true

  alias Breeze.Theme

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
    assert Theme.color(theme, :panel) == {47, 48, 49}
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

  test "builtin themes can be loaded by name and variant" do
    light = Theme.builtin(:solarized, :light)
    dark = Theme.builtin(:solarized, :dark)

    assert light.name == "solarized-light"
    assert dark.name == "solarized-dark"
    assert Theme.color(dark, :background) == {0, 43, 54}
    assert Theme.color(dark, :panel) == {10, 58, 69}
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
