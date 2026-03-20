defmodule Breeze.Implicit.Dropdown do
  @moduledoc false

  def init(children, last_state), do: init(children, %{}, last_state)

  def init(children, root_attrs, last_state) do
    items = Enum.filter(children, &Map.get(&1, :"dropdown-item"))
    values = Enum.map(items, &Map.get(&1, :value))

    selected_index =
      case Map.get(last_state, :selected) || Map.get(root_attrs, :"dropdown-selected") do
        nil -> 0
        selected -> Enum.find_index(values, &(&1 == selected)) || 0
      end

    selected_index = min(selected_index, max(length(values) - 1, 0))
    selected = Enum.at(values, selected_index)
    open? = Map.get(last_state, :open?, false)

    %{
      values: values,
      selected: selected,
      selected_index: selected_index,
      highlighted_index:
        normalize_index(Map.get(last_state, :highlighted_index, selected_index), values),
      open?: open?,
      trigger_width: int_option(root_attrs, :"dropdown-trigger-width", 10),
      menu_width: int_option(root_attrs, :"dropdown-menu-width", 12),
      menu_height: int_option(root_attrs, :"dropdown-menu-height", length(values) + 2),
      menu_left: int_option(root_attrs, :"dropdown-menu-left", 0),
      menu_top: int_option(root_attrs, :"dropdown-menu-top", 1)
    }
  end

  def handle_event(_, %{"key" => key}, %{open?: false} = state)
      when key in ["Enter", " ", "\x14", "ArrowDown", "ArrowUp", "j", "k"] do
    {:noreply, open(state)}
  end

  def handle_event(_, %{"key" => "Escape"}, %{open?: true} = state) do
    {:noreply, close(state)}
  end

  def handle_event(_, %{"key" => "\x14"}, %{open?: true} = state) do
    {:noreply, close(state)}
  end

  def handle_event(_, %{"key" => key}, %{open?: true} = state)
      when key in ["ArrowDown", "j"] do
    {:noreply, %{state | highlighted_index: next_index(state, 1)}}
  end

  def handle_event(_, %{"key" => key}, %{open?: true} = state)
      when key in ["ArrowUp", "k"] do
    {:noreply, %{state | highlighted_index: next_index(state, -1)}}
  end

  def handle_event(_, %{"key" => key}, %{open?: true} = state) when key in ["Enter", " "] do
    selected_index = state.highlighted_index || state.selected_index
    selected = Enum.at(state.values, selected_index)

    next_state = %{
      close(state)
      | selected: selected,
        selected_index: selected_index,
        highlighted_index: selected_index
    }

    {{:change, %{value: selected, index: selected_index}}, next_state}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, _state), do: []

  def handle_modifiers(:child, flags, state) do
    cond do
      Keyword.get(flags, :"dropdown-indicator-open") && not state.open? ->
        [style: indicator_style(state, hidden?: true)]

      Keyword.get(flags, :"dropdown-indicator-open") ->
        [style: indicator_style(state)]

      Keyword.get(flags, :"dropdown-indicator-closed") && state.open? ->
        [style: indicator_style(state, hidden?: true)]

      Keyword.get(flags, :"dropdown-indicator-closed") ->
        [style: indicator_style(state)]

      Keyword.get(flags, :"dropdown-frame") && not state.open? ->
        [style: "absolute left-0 top-0 width-0 height-0 overflow-hidden layer-20"]

      Keyword.get(flags, :"dropdown-frame") ->
        [style: frame_style(state)]

      Keyword.get(flags, :"dropdown-item") && not state.open? ->
        [style: "absolute left-0 top-0 width-0 height-0 overflow-hidden layer-21"]

      Keyword.get(flags, :"dropdown-item") &&
          Enum.at(state.values, state.highlighted_index) == Keyword.get(flags, :value) ->
        [selected: true, style: item_style(state, flags)]

      Keyword.get(flags, :"dropdown-item") ->
        [style: item_style(state, flags)]

      true ->
        []
    end
  end

  defp frame_style(state),
    do:
      "absolute left-#{state.menu_left} top-#{state.menu_top} width-#{state.menu_width} height-#{state.menu_height} bg-panel text overflow-hidden layer-20"

  defp item_style(state, flags) do
    index = int_flag(flags, :"dropdown-item-index", 0)

    "absolute left-#{state.menu_left} top-#{state.menu_top + index} bg-panel text width-#{state.menu_width} layer-21"
  end

  defp indicator_style(state, opts \\ []) do
    hidden? = Keyword.get(opts, :hidden?, false)
    width = if hidden?, do: 0, else: 1
    height = if hidden?, do: 0, else: 1
    overflow = if hidden?, do: " overflow-hidden", else: ""

    "absolute left-#{max(state.trigger_width - 2, 0)} top-0 width-#{width} height-#{height}#{overflow}"
  end

  defp int_flag(flags, key, default) do
    case Keyword.get(flags, key) do
      nil -> default
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> default
    end
  rescue
    _ -> default
  end

  def open(state) do
    %{state | open?: true, highlighted_index: state.selected_index}
  end

  def close(state) do
    %{state | open?: false, highlighted_index: state.selected_index}
  end

  def blur(state), do: close(state)

  defp next_index(%{values: []}, _delta), do: 0

  defp next_index(%{values: values, highlighted_index: index}, delta) do
    rem((index || 0) + delta + length(values), length(values))
  end

  defp normalize_index(index, []) when is_integer(index), do: index
  defp normalize_index(_index, []), do: 0

  defp normalize_index(index, values) when is_integer(index) do
    index
    |> max(0)
    |> min(length(values) - 1)
  end

  defp normalize_index(_index, values), do: min(length(values) - 1, 0)

  defp int_option(attrs, key, default) do
    case Map.get(attrs, key) do
      nil -> default
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> default
    end
  rescue
    _ -> default
  end
end
