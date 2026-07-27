defmodule Breeze.Implicit.Scroll do
  @moduledoc false

  @behaviour Breeze.Implicit

  _ = """
  Built-in implicit module for keyboard-scrollable content areas.

  Supports Up/Down/PageUp/PageDown/Home/End for vertical scrolling.
  """

  alias Breeze.Implicit.Common
  alias Breeze.Viewport

  def init(_children, root_attrs, last_state) do
    autoscroll =
      Map.get(root_attrs, :"scroll-autoscroll", Map.get(last_state, :autoscroll))

    state = %{
      offset_y: Map.get(last_state, :offset_y, 0),
      autoscroll: autoscroll,
      pinned_bottom: Map.get(last_state, :pinned_bottom, autoscroll == "bottom")
    }

    {:ok, state, requires_layout_rerender: true}
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowDown", "j"] do
    viewport = Viewport.from_dimensions(element)
    current_offset_y = effective_offset_y(state, viewport)
    offset_y = Viewport.clamp_scroll_y(current_offset_y + 1, viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowUp", "k"] do
    viewport = Viewport.from_dimensions(element)
    current_offset_y = effective_offset_y(state, viewport)
    offset_y = Viewport.clamp_scroll_y(current_offset_y - 1, viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"key" => "PageDown", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    current_offset_y = effective_offset_y(state, viewport)
    offset_y = Viewport.clamp_scroll_y(current_offset_y + jump, viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    current_offset_y = effective_offset_y(state, viewport)
    offset_y = Viewport.clamp_scroll_y(current_offset_y - jump, viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"key" => "Home", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    {:noreply, put_offset(state, 0, viewport)}
  end

  def handle_event(_, %{"key" => "End", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    offset_y = Viewport.max_scroll_y(viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(
        _,
        %{"mouse" => %{"button" => "wheel_down"} = mouse, "element" => element},
        state
      ) do
    viewport = Viewport.from_dimensions(element)
    current_offset_y = effective_offset_y(state, viewport)

    offset_y =
      Viewport.clamp_scroll_y(
        current_offset_y + wheel_step(viewport) * wheel_repeat(mouse),
        viewport
      )

    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(
        _,
        %{"mouse" => %{"button" => "wheel_up"} = mouse, "element" => element},
        state
      ) do
    viewport = Viewport.from_dimensions(element)
    current_offset_y = effective_offset_y(state, viewport)

    offset_y =
      Viewport.clamp_scroll_y(
        current_offset_y - wheel_step(viewport) * wheel_repeat(mouse),
        viewport
      )

    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, flags, state),
    do: [scroll_y: effective_offset_y(state, Keyword.get(flags, :layout_element))]

  def handle_modifiers(:child, _flags, _state), do: []

  defp wheel_step(%Viewport{viewport_height: height}) do
    max(div(height, 2), 1)
  end

  defp wheel_repeat(mouse), do: Common.wheel_repeat(mouse)

  defp effective_offset_y(state, nil), do: Map.get(state, :offset_y, 0)

  defp effective_offset_y(state, %Viewport{} = viewport) do
    cond do
      state[:autoscroll] == "bottom" and Map.get(state, :pinned_bottom, true) ->
        Viewport.max_scroll_y(viewport)

      true ->
        Viewport.clamp_scroll_y(Map.get(state, :offset_y, 0), viewport)
    end
  end

  defp put_offset(state, offset_y, viewport) do
    max_offset = Viewport.max_scroll_y(viewport)

    state
    |> Map.put(:offset_y, offset_y)
    |> Map.put(:pinned_bottom, state[:autoscroll] == "bottom" and offset_y >= max_offset)
  end
end
