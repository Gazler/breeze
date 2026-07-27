defmodule ThemeDemo do
  use Breeze.View

  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok, switch_theme(term, :nebula)}
  end

  def render(assigns) do
    ~H"""
    <box class="w-screen h-screen bg text">
      <.panel id="theme-demo" width={85} height={20} class="border bg-panel">
        <:title>
          Theme Demo ({@breeze.theme.name}/{@breeze.theme.actual_mode} - {@breeze.theme.status})
        </:title>
        <box class="text-primary font-bold w-full">Semantic theme tokens</box>
        <box class="text-muted w-full">
          1 system16  2 system  3 nebula  4 catppuccin  5 dracula  6 commander  7 gruvbox  8 nord  9 solarized-light  0 solarized-dark
        </box>
        <box class="text-muted w-full">
          Semantic `class` tokens and inline `style` maps work together.
        </box>
        <box class="h-1">
        </box>
        <box class="inline">
          <box class="w-12 text-primary">Primary</box>
          <box class="w-12 text-secondary">Secondary</box>
          <box class="w-12 text-success">Success</box>
          <box class="w-12 text-warning">Warning</box>
          <box class="w-12 text-error">Error</box>
          <box class="w-12 text-accent">Accent</box>
        </box>
        <box class="h-1">
        </box>
        <box class="inline">
          <box
            style={%{width: 12, height: 3, background_color: :surface, foreground_color: :text, border: :line}}
          >
            Text
          </box>
          <box class="w-1">
          </box>
          <box
            style={%{width: 12, height: 3, background_color: :background, foreground_color: :muted, border: :line}}
          >
            Muted
          </box>
          <box class="w-1">
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
          <box class="w-1">
          </box>
          <box
            style={%{width: 12, height: 3, background_color: :background, foreground_color: :text, border: :line}}
          >
            Background
          </box>
          <box class="w-1">
          </box>
          <box
            style={%{width: 12, height: 3, background_color: :surface, foreground_color: :text, border: :line}}
          >
            Surface
          </box>
        </box>
        <box class="h-1">
        </box>
        <box class="inline">
          <box class="w-14 h-3 border text-fg bg-surface">text-fg</box>
          <box class="w-2">
          </box>
          <box class="w-14 h-3 border text-bg bg-primary">text-bg</box>
          <box class="w-2">
          </box>
          <box
            style={%{width: 14, height: 3, background_color: :surface, foreground_color: :text, border: :line}}
          >
            surface
          </box>
          <box class="w-2">
          </box>
          <box
            style={%{width: 14, height: 3, background_color: :panel, foreground_color: :text, border: :line}}
          >
            panel
          </box>
          <box class="w-2">
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
        <box class="h-1">
        </box>
      </.panel>
    </box>
    """
  end

  def handle_event(_, %{"key" => "1"}, term),
    do: {:noreply, switch_theme(term, :system16)}

  def handle_event(_, %{"key" => "2"}, term),
    do: {:noreply, switch_theme(term, :system)}

  def handle_event(_, %{"key" => "3"}, term),
    do: {:noreply, switch_theme(term, :nebula)}

  def handle_event(_, %{"key" => "4"}, term),
    do: {:noreply, switch_theme(term, :catppuccin)}

  def handle_event(_, %{"key" => "5"}, term),
    do: {:noreply, switch_theme(term, :dracula)}

  def handle_event(_, %{"key" => "6"}, term),
    do: {:noreply, switch_theme(term, :commander)}

  def handle_event(_, %{"key" => "7"}, term),
    do: {:noreply, switch_theme(term, :gruvbox)}

  def handle_event(_, %{"key" => "8"}, term),
    do: {:noreply, switch_theme(term, :nord)}

  def handle_event(_, %{"key" => "9"}, term),
    do: {:noreply, switch_theme(term, :solarized_light)}

  def handle_event(_, %{"key" => "0"}, term),
    do: {:noreply, switch_theme(term, :solarized_dark)}

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Example.run(
  [
    view: ThemeDemo,
    reload: true,
    theme: :system,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
