defmodule Breeze.Theme.Builtin do
  @moduledoc """
  Built-in Breeze themes.
  """

  alias Breeze.Theme

  @spec fetch!(atom(), atom() | nil) :: Theme.t()
  def fetch!(name, variant \\ nil)

  def fetch!(:nebula, nil), do: nebula()
  def fetch!(:catppuccin, nil), do: catppuccin()
  def fetch!(:catppuccin, :dark), do: catppuccin()
  def fetch!(:dracula, nil), do: dracula()
  def fetch!(:gruvbox, nil), do: gruvbox()
  def fetch!(:gruvbox, :dark), do: gruvbox()
  def fetch!(:nord, nil), do: nord()
  def fetch!(:solarized, :light), do: solarized_light()
  def fetch!(:solarized, :dark), do: solarized_dark()
  def fetch!(:solarized_light, nil), do: solarized_light()
  def fetch!(:solarized_dark, nil), do: solarized_dark()

  def fetch!(name, variant) do
    raise ArgumentError,
          "unknown built-in theme #{inspect(name)}" <>
            if(variant, do: " with variant #{inspect(variant)}", else: "")
  end

  def nebula do
    Theme.new(
      name: "nebula",
      defaults: %{
        foreground_color: "#D6E7FF",
        background_color: "#0D2137",
        border_color: "#4A9CFF"
      },
      palette: %{
        muted: "#7DA3C8",
        primary: "#4A9CFF",
        secondary: "#66D9EF",
        warning: "#FFB454",
        error: "#FF5555",
        success: "#50FA7B",
        accent: "#FF79C6",
        surface: "#193549",
        panel: "#1F4662"
      },
      extras: %{cursor: "#FF79C6"}
    )
  end

  def catppuccin do
    Theme.new(
      name: "catppuccin-mocha",
      defaults: %{
        foreground_color: "#CDD6F4",
        background_color: "#181825",
        border_color: "#7F849C"
      },
      palette: %{
        muted: "#A6ADC8",
        primary: "#F5C2E7",
        secondary: "#CBA6F7",
        warning: "#FAE3B0",
        error: "#F28FAD",
        success: "#ABE9B3",
        accent: "#FAB387",
        surface: "#313244",
        panel: "#45475A"
      },
      extras: %{cursor: "#F5E0DC"}
    )
  end

  def dracula do
    Theme.new(
      name: "dracula",
      defaults: %{
        foreground_color: "#F8F8F2",
        background_color: "#282A36",
        border_color: "#6272A4"
      },
      palette: %{
        muted: "#B6B6AE",
        primary: "#8BE9FD",
        secondary: "#BD93F9",
        warning: "#F1FA8C",
        error: "#FF5555",
        success: "#50FA7B",
        accent: "#FF79C6",
        surface: "#44475A",
        panel: "#383A59"
      },
      extras: %{cursor: "#F8F8F2"}
    )
  end

  def gruvbox do
    Theme.new(
      name: "gruvbox-dark",
      defaults: %{
        foreground_color: "#EBDBB2",
        background_color: "#282828",
        border_color: "#928374"
      },
      palette: %{
        muted: "#A89984",
        primary: "#83A598",
        secondary: "#8EC07C",
        warning: "#FABD2F",
        error: "#FB4934",
        success: "#B8BB26",
        accent: "#D3869B",
        surface: "#3C3836",
        panel: "#32302F"
      },
      extras: %{cursor: "#EBDBB2"}
    )
  end

  def nord do
    Theme.new(
      name: "nord",
      defaults: %{
        foreground_color: "#ECEFF4",
        background_color: "#242933",
        border_color: "#4C566A"
      },
      palette: %{
        muted: "#D8DEE9",
        primary: "#88C0D0",
        secondary: "#81A1C1",
        warning: "#EBCB8B",
        error: "#BF616A",
        success: "#A3BE8C",
        accent: "#B48EAD",
        surface: "#3B4252",
        panel: "#2E3440"
      },
      extras: %{cursor: "#D8DEE9"}
    )
  end

  def solarized_light do
    Theme.new(
      name: "solarized-light",
      defaults: %{
        foreground_color: "#586E75",
        background_color: "#FFFDF6",
        border_color: "#93A1A1"
      },
      palette: %{
        muted: "#93A1A1",
        primary: "#268BD2",
        secondary: "#2AA198",
        warning: "#B58900",
        error: "#DC322F",
        success: "#859900",
        accent: "#6C71C4",
        surface: "#EEE8D5",
        panel: "#FDF6E3"
      },
      extras: %{cursor: "#657B83"}
    )
  end

  def solarized_dark do
    Theme.new(
      name: "solarized-dark",
      defaults: %{
        foreground_color: "#839496",
        background_color: "#002B36",
        border_color: "#586E75"
      },
      palette: %{
        muted: "#657B83",
        primary: "#268BD2",
        secondary: "#2AA198",
        warning: "#B58900",
        error: "#DC322F",
        success: "#859900",
        accent: "#6C71C4",
        surface: "#073642",
        panel: "#0A3A45"
      },
      extras: %{cursor: "#839496"}
    )
  end
end
