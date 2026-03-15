defmodule Breeze.Implicit.Scroll do
  @moduledoc false

  _ = """
  Built-in implicit module for keyboard-scrollable content areas.

  Supports Up/Down/PageUp/PageDown/Home/End for vertical scrolling.
  """

  alias Breeze.Viewport

  def init(children, last_state), do: init(children, %{}, last_state)

  def init(_children, root_attrs, last_state) do
    autoscroll =
      Map.get(root_attrs, :"scroll-autoscroll", Map.get(last_state, :autoscroll))

    %{
      offset_y: Map.get(last_state, :offset_y, 0),
      autoscroll: autoscroll,
      pinned_bottom: Map.get(last_state, :pinned_bottom, autoscroll == "bottom")
    }
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowDown", "j"] do
    viewport = Viewport.from_dimensions(element)
    offset_y = Viewport.clamp_scroll_y(state.offset_y + 1, viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowUp", "k"] do
    viewport = Viewport.from_dimensions(element)
    offset_y = Viewport.clamp_scroll_y(state.offset_y - 1, viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"key" => "PageDown", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    offset_y = Viewport.clamp_scroll_y(state.offset_y + jump, viewport)
    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    offset_y = Viewport.clamp_scroll_y(state.offset_y - jump, viewport)
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

  def handle_event(_, %{"mouse" => %{button: :wheel_down} = mouse, "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)

    offset_y =
      Viewport.clamp_scroll_y(
        state.offset_y + wheel_step(viewport) * wheel_repeat(mouse),
        viewport
      )

    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, %{"mouse" => %{button: :wheel_up} = mouse, "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)

    offset_y =
      Viewport.clamp_scroll_y(
        state.offset_y - wheel_step(viewport) * wheel_repeat(mouse),
        viewport
      )

    {:noreply, put_offset(state, offset_y, viewport)}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, state), do: [scroll_y: state.offset_y]
  def handle_modifiers(:child, _flags, _state), do: []

  def reconcile(%Viewport{} = viewport, state) do
    offset_y =
      cond do
        state[:autoscroll] == "bottom" and Map.get(state, :pinned_bottom, true) ->
          Viewport.max_scroll_y(viewport)

        true ->
          Viewport.clamp_scroll_y(Map.get(state, :offset_y, 0), viewport)
      end

    put_offset(state, offset_y, viewport)
  end

  def reconcile(viewport, state), do: reconcile(Viewport.from_dimensions(viewport), state)

  defp wheel_step(%Viewport{viewport_height: height}) do
    max(div(height, 2), 1)
  end

  defp wheel_repeat(%{repeat: repeat}) when is_integer(repeat) and repeat > 0, do: repeat
  defp wheel_repeat(_mouse), do: 1

  defp put_offset(state, offset_y, viewport) do
    max_offset = Viewport.max_scroll_y(viewport)

    state
    |> Map.put(:offset_y, offset_y)
    |> Map.put(:pinned_bottom, state[:autoscroll] == "bottom" and offset_y >= max_offset)
  end
end
