defmodule Breeze.Implicit.Table do
  @moduledoc false

  alias Breeze.Implicit.Common
  alias Breeze.Viewport

  @type state :: %{
          values: list(),
          selected: term() | nil,
          selected_index: non_neg_integer() | nil,
          offset: non_neg_integer(),
          loop: boolean(),
          scroll_padding: non_neg_integer()
        }

  def init(children, last_state), do: init(children, %{}, last_state)

  def init(children, root_attrs, last_state) do
    values =
      children
      |> Enum.filter(&Map.get(&1, :"table-row"))
      |> Enum.map(& &1.value)

    selected_index =
      values
      |> pick_selected_index(last_state, root_attrs)
      |> Common.normalize_selected_index(values)

    selected = Common.selected_value(values, selected_index)

    %{
      values: values,
      selected: selected,
      selected_index: selected_index,
      offset: Common.normalize_int(Map.get(last_state, :offset, 0)),
      loop: Common.bool_option(root_attrs, :"table-loop", Map.get(last_state, :loop, true)),
      scroll_padding:
        Common.int_option(
          root_attrs,
          :"table-scroll-padding",
          Map.get(last_state, :scroll_padding, 0),
          clamp: false
        )
    }
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowDown", "j"] do
    state
    |> move_selection(1, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowUp", "k"] do
    state
    |> move_selection(-1, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "Home", "element" => element}, state) do
    state
    |> set_selection(0, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "End", "element" => element}, state) do
    state
    |> set_selection(max(length(state.values) - 1, 0), element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageDown", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)

    state
    |> set_selection((state.selected_index || 0) + jump, viewport)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)

    state
    |> set_selection((state.selected_index || 0) - jump, viewport)
    |> maybe_change()
  end

  def handle_event(
        _,
        %{"mouse" => %{button: :left, action: :press}, "row" => row, "element" => element},
        state
      )
      when is_integer(row) and row >= 0 do
    state
    |> set_selection(row + state.offset, element)
    |> maybe_change()
  end

  def handle_event(_, %{"mouse" => %{button: :wheel_down} = mouse, "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    offset = Viewport.clamp_scroll_y(state.offset + Common.wheel_repeat(mouse), viewport)
    {:noreply, %{state | offset: offset}}
  end

  def handle_event(_, %{"mouse" => %{button: :wheel_up} = mouse, "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    offset = Viewport.clamp_scroll_y(state.offset - Common.wheel_repeat(mouse), viewport)
    {:noreply, %{state | offset: offset}}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, state), do: Common.root_scroll_modifier(state)

  def handle_modifiers(:child, flags, state) do
    cond do
      Keyword.get(flags, :"table-row") && state.selected == Keyword.get(flags, :value) ->
        [selected: true]

      true ->
        []
    end
  end

  defp move_selection(%{values: []} = state, _delta, _element), do: state

  defp move_selection(state, delta, element) do
    state
    |> Common.next_index(delta)
    |> then(&set_selection(state, &1, element))
  end

  defp set_selection(%{values: []} = state, _index, _element), do: state

  defp set_selection(state, index, element) do
    index = Common.normalize_selected_index(index, state.values)
    selected = Common.selected_value(state.values, index)
    viewport = Viewport.from_dimensions(element)

    offset =
      if index do
        Viewport.ensure_row_visible(state.offset, index, viewport, padding: state.scroll_padding)
      else
        Viewport.clamp_scroll_y(state.offset, viewport)
      end

    %{state | selected_index: index, selected: selected, offset: offset}
  end

  defp maybe_change(state), do: Common.change_reply(state)

  defp pick_selected_index(values, last_state, root_attrs) do
    cond do
      Map.has_key?(root_attrs, :"table-selected") ->
        Enum.find_index(values, &(&1 == Map.get(root_attrs, :"table-selected")))

      Map.has_key?(root_attrs, :"table-initial-index") ->
        Common.int_option(root_attrs, :"table-initial-index", nil, clamp: false)

      Map.has_key?(last_state, :selected) ->
        Enum.find_index(values, &(&1 == Map.get(last_state, :selected)))

      true ->
        nil
    end
  end
end
