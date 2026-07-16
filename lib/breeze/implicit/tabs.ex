defmodule Breeze.Implicit.Tabs do
  @moduledoc false

  @behaviour Breeze.Implicit

  def init(children, root_attrs, last_state) do
    tab_items = Enum.filter(children, &Map.has_key?(&1, :"tab-label"))
    values = Enum.map(tab_items, & &1.value)

    widths =
      Enum.map(tab_items, fn item ->
        label = Map.get(item, :"tab-label", "")
        String.length(label) + 2
      end)

    selected_index =
      case Map.get(root_attrs, :"tab-selected") do
        nil ->
          case Map.get(last_state, :selected) do
            nil -> 0
            selected -> Enum.find_index(values, &(&1 == selected)) || 0
          end

        selected ->
          Enum.find_index(values, &(&1 == selected)) || 0
      end

    selected_index = min(selected_index, max(length(values) - 1, 0))
    selected = Enum.at(values, selected_index)
    offset_x = Map.get(last_state, :offset_x, 0)

    viewport_width =
      case Map.get(last_state, :__element__) do
        nil -> Map.get(last_state, :viewport_width)
        el -> el.viewport_width
      end

    {:ok,
     %{
       values: values,
       widths: widths,
       selected: selected,
       selected_index: selected_index,
       offset_x: offset_x,
       viewport_width: viewport_width,
       delegate_target: Map.get(root_attrs, :"tab-delegate"),
       target_prefix: root_attrs |> Map.get(:id, "") |> Kernel.<>("-tab-")
     }}
  end

  def handle_event(_, %{"key" => key}, %{values: []} = state) when key in ["ArrowRight", "l"] do
    {:noreply, state}
  end

  def handle_event(_, %{"key" => key}, state) when key in ["ArrowRight", "l"] do
    count = length(state.values)
    next = rem(state.selected_index + 1, count)
    next_state = %{state | selected_index: next, selected: Enum.at(state.values, next)}
    emit_change(%{next_state | offset_x: compute_offset_x(next_state)})
  end

  def handle_event(_, %{"key" => key}, %{values: []} = state) when key in ["ArrowLeft", "h"] do
    {:noreply, state}
  end

  def handle_event(_, %{"key" => key}, state) when key in ["ArrowLeft", "h"] do
    count = length(state.values)
    prev = rem(state.selected_index - 1 + count, count)
    prev_state = %{state | selected_index: prev, selected: Enum.at(state.values, prev)}
    emit_change(%{prev_state | offset_x: compute_offset_x(prev_state)})
  end

  def handle_event(_, %{"key" => key}, %{delegate_target: target} = state)
      when key in ["ArrowDown", "ArrowUp", "j", "k", "PageDown", "PageUp", "Home", "End"] and
             is_binary(target) do
    {{:delegate, target}, state}
  end

  def handle_event(
        _,
        %{"mouse" => %{"button" => "left", "action" => "press"}, "target" => target},
        state
      )
      when is_binary(target) do
    case clicked_value(state, target) do
      nil ->
        {:noreply, state}

      value ->
        index = Enum.find_index(state.values, &(&1 == value)) || state.selected_index
        next_state = %{state | selected: value, selected_index: index}
        emit_change(%{next_state | offset_x: compute_offset_x(next_state)})
    end
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, _state), do: []

  def handle_modifiers(:child, flags, state) do
    cond do
      Keyword.has_key?(flags, :"tab-bar") ->
        [scroll_x: state.offset_x]

      Keyword.get(flags, :"tab-indicator-active") &&
          state.selected == Keyword.get(flags, :"tab-value") ->
        []

      Keyword.get(flags, :"tab-indicator-active") ->
        [style: "width-0 height-0 overflow-hidden"]

      Keyword.get(flags, :"tab-indicator-inactive") &&
          state.selected == Keyword.get(flags, :"tab-value") ->
        [style: "width-0 height-0 overflow-hidden"]

      Keyword.get(flags, :"tab-indicator-inactive") ->
        []

      state.selected == Keyword.get(flags, :value) ->
        [selected: true]

      true ->
        []
    end
  end

  defp compute_offset_x(%{
         widths: widths,
         selected_index: selected_index,
         offset_x: current_offset,
         viewport_width: viewport_width
       }) do
    if is_nil(viewport_width) or viewport_width <= 0 do
      current_offset
    else
      tab_starts = prefix_offsets(widths)
      cumulative = Enum.at(tab_starts, selected_index, 0)
      tab_width = Enum.at(widths, selected_index, 0)
      selected_end = cumulative + tab_width

      cond do
        cumulative < current_offset ->
          cumulative

        selected_end > current_offset + viewport_width ->
          tab_starts
          |> Enum.take(selected_index + 1)
          |> Enum.filter(fn start -> selected_end - start <= viewport_width end)
          |> case do
            [start | _] -> start
            [] -> cumulative
          end

        true ->
          current_offset
      end
    end
  end

  defp prefix_offsets(widths) do
    {offsets, _acc} =
      Enum.map_reduce(widths, 0, fn width, offset ->
        {offset, offset + width}
      end)

    offsets
  end

  defp emit_change(state) do
    {{:change, %{value: state.selected, index: state.selected_index}}, state}
  end

  defp clicked_value(%{target_prefix: prefix, values: values}, target) do
    with true <- prefix != "-tab-",
         value when is_binary(value) <- String.trim_leading(target, prefix),
         true <- value != target,
         true <- value in values do
      value
    else
      _ -> nil
    end
  end
end
