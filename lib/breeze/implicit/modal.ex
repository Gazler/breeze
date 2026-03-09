defmodule Breeze.Implicit.Modal do
  @moduledoc false

  def init(_items, last_state), do: last_state

  def init(_items, root_attrs, last_state) do
    width = dimension(root_attrs, :width, Map.get(last_state, :width, 0))
    height = dimension(root_attrs, :height, Map.get(last_state, :height, 0))
    screen_width = dimension(root_attrs, :"screen-width", Map.get(last_state, :screen_width, 0))

    screen_height =
      dimension(root_attrs, :"screen-height", Map.get(last_state, :screen_height, 0))

    frame_width = width + 2
    frame_height = height + 2

    %{
      width: width,
      height: height,
      frame_width: frame_width,
      frame_height: frame_height,
      screen_width: screen_width,
      screen_height: screen_height,
      left: div(max(screen_width - frame_width, 0), 2),
      top: div(max(screen_height - frame_height, 0), 2)
    }
  end

  def handle_event(_, %{"key" => "Escape"}, state) do
    {{:change, %{action: :close}}, state}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, state) do
    [style: "absolute left-#{state.left} top-#{state.top}"]
  end

  def handle_modifiers(:child, _flags, _state), do: []

  defp dimension(attrs, key, fallback) do
    case Map.get(attrs, key, fallback) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> fallback
    end
  end
end
