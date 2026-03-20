defmodule ThemeDemo do
  use Breeze.View

  import Breeze.Blocks

  alias Breeze.Theme

  def mount(_opts, term) do
    term = put_theme(term, Theme.builtin(:nebula))
    {:ok, assign(term, mode: :nebula, actual_theme_mode: term.theme.mode, theme_status: :ready)}
  end

  def render(assigns) do
    ~H"""
    <box class="width-screen height-screen bg text">
      <.panel
        id="theme-demo"
        width={76}
        height={18}
        scroll
        class="border bg-surface"
        scroll_class="bg-surface"
      >
        <:title>Theme Demo</:title>
        <box class="text-primary bold width-full">Semantic theme tokens</box>
        <box class="text-muted width-full">
          1 system16  2 system  3 nebula  4 catppuccin  5 dracula  6 gruvbox  7 nord  8 solarized-light  9 solarized-dark
        </box>
        <box class="text-muted width-full">
          Semantic `class` tokens and inline `style` maps work together.
        </box>
        <box class="height-1">
        </box>
        <box class="inline">
          <box class="width-12 text-primary">Primary</box>
          <box class="width-12 text-secondary">Secondary</box>
          <box class="width-12 text-success">Success</box>
          <box class="width-12 text-warning">Warning</box>
          <box class="width-12 text-error">Error</box>
          <box class="width-12 text-accent">Accent</box>
        </box>
        <box class="height-1">
        </box>
        <box class="inline">
          <box
            style={%{width: 12, height: 3, background_color: :surface, foreground_color: :text, border: :line}}
          >
            Text
          </box>
          <box class="width-1">
          </box>
          <box
            style={%{width: 12, height: 3, background_color: :surface, foreground_color: :muted, border: :line}}
          >
            Muted
          </box>
          <box class="width-1">
          </box>
          <box
            style={%{
      width: 12,
      height: 3,
      background_color: :surface,
      foreground_color: :text,
      border: :line,
      border_color: :stroke
    }}
          >
            Border
          </box>
          <box class="width-1">
          </box>
          <box
            style={%{width: 12, height: 3, background_color: :background, foreground_color: :text, border: :line}}
          >
            Background
          </box>
          <box class="width-1">
          </box>
          <box
            style={%{width: 12, height: 3, background_color: :surface, foreground_color: :text, border: :line}}
          >
            Surface
          </box>
        </box>
        <box class="height-1">
        </box>
        <box class="inline">
          <box
            style={%{width: 14, height: 3, background_color: :surface, foreground_color: :text, border: :line}}
          >
            surface
          </box>
          <box class="width-2">
          </box>
          <box
            style={%{width: 14, height: 3, background_color: :panel, foreground_color: :text, border: :line}}
          >
            panel
          </box>
          <box class="width-2">
          </box>
          <box
            style={%{
      width: 18,
      height: 3,
      background_color: :background,
      foreground_color: :primary,
      border: :rounded
    }}
          >
            inline style map
          </box>
        </box>
        <box class="height-1">
        </box>
        <box class="border border-accent bg-panel width-42">
          Current theme: {@mode}/{@actual_theme_mode} ({@theme_status})
        </box>
      </.panel>
    </box>
    """
  end

  def handle_event(_, %{"key" => "1"}, term),
    do: {:noreply, assign_theme(term, :system16, Theme.system16())}

  def handle_event(_, %{"key" => "2"}, term),
    do: {:noreply, assign_theme(term, :system, Theme.system())}

  def handle_event(_, %{"key" => "3"}, term),
    do: {:noreply, assign_theme(term, :nebula, Theme.builtin(:nebula))}

  def handle_event(_, %{"key" => "4"}, term),
    do: {:noreply, assign_theme(term, :catppuccin, Theme.builtin(:catppuccin))}

  def handle_event(_, %{"key" => "5"}, term),
    do: {:noreply, assign_theme(term, :dracula, Theme.builtin(:dracula))}

  def handle_event(_, %{"key" => "6"}, term),
    do: {:noreply, assign_theme(term, :gruvbox, Theme.builtin(:gruvbox))}

  def handle_event(_, %{"key" => "7"}, term),
    do: {:noreply, assign_theme(term, :nord, Theme.builtin(:nord))}

  def handle_event(_, %{"key" => "8"}, term),
    do: {:noreply, assign_theme(term, :solarized_light, Theme.builtin(:solarized, :light))}

  def handle_event(_, %{"key" => "9"}, term),
    do: {:noreply, assign_theme(term, :solarized_dark, Theme.builtin(:solarized, :dark))}

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}

  defp assign_theme(term, mode, theme) do
    term = put_theme(term, theme)

    assign(term,
      mode: mode,
      actual_theme_mode: term.theme.mode,
      theme_status: Breeze.Theme.probe_status(term.theme) || :ready
    )
  end
end

Breeze.Example.run(
  [
    view: ThemeDemo,
    reload: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
