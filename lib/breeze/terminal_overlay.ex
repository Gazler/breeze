defmodule Breeze.TerminalOverlay do
  @moduledoc false
  @blink_interval_ms 500
  @recent_interaction_ms @blink_interval_ms * 2

  def write_overlays(terminal, overlays) when is_list(overlays) do
    overlay_output = render_overlays(overlays)

    if overlay_output == "" do
      terminal
    else
      Termite.Terminal.write(terminal, overlay_output)
    end
  end

  def render_overlays(overlays) when is_list(overlays) do
    Enum.map_join(overlays, "", &render_overlay/1)
  end

  def render_overlay(nil), do: ""

  def render_overlay(%{visible?: false}), do: ""

  def render_overlay(%{x: x, y: y, content: content}) when is_binary(content) do
    position = cursor_position_code(x, y)
    position <> content <> position
  end

  def render_overlay(%{x: x, y: y, char: char}) do
    position = cursor_position_code(x, y)
    content = cursor_open_code() <> char <> Termite.Style.reset_code()
    position <> content <> position
  end

  def visible?(now_ms, last_interaction_at) when is_integer(now_ms) do
    recent_interaction?(now_ms, last_interaction_at) or blink_visible?(now_ms)
  end

  def blink_visible?(now_ms) when is_integer(now_ms) do
    rem(div(now_ms, @blink_interval_ms), 2) == 0
  end

  def next_blink_delay(now_ms) when is_integer(now_ms) do
    case rem(now_ms, @blink_interval_ms) do
      0 -> @blink_interval_ms
      rem_ms -> @blink_interval_ms - rem_ms
    end
  end

  defp recent_interaction?(now_ms, last_interaction_at)
       when is_integer(now_ms) and is_integer(last_interaction_at) do
    now_ms - last_interaction_at < @recent_interaction_ms
  end

  defp recent_interaction?(_now_ms, _last_interaction_at), do: false

  defp cursor_open_code do
    Termite.Style.ansi256()
    |> Termite.Style.foreground(0)
    |> Termite.Style.background(11)
    |> Termite.Style.open_code()
  end

  defp cursor_position_code(x, y), do: "\e[#{y + 1};#{x + 1}H"
end
