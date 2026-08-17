defmodule Breeze.Implicit.List do
  @moduledoc false

  @behaviour Breeze.Implicit
  _ = """
  Built-in implicit module for keyboard-navigable list views.

  ## Root options

  Set these on the root implicit box via attributes:

    * `list-loop` - wrap selection at edges (`true` by default)
    * `list-scroll-padding` - keep N rows of breathing room around selection
    * `list-selected` - initial selected value
    * `list-initial-index` - initial selected index

  Child boxes should define a `value` attribute.
  """

  alias Breeze.Implicit.Common
  alias Breeze.Viewport

  def init(children, root_attrs, last_state) do
    values = values_from_attrs(root_attrs, children)

    loop =
      Common.bool_option(root_attrs, :"list-loop", Map.get(last_state, :loop, true),
        numeric: true
      )

    scroll_padding =
      Common.int_option(
        root_attrs,
        :"list-scroll-padding",
        Map.get(last_state, :scroll_padding, 0)
      )

    width = Common.int_option(root_attrs, :"list-width", Map.get(last_state, :width, 0))

    cache = build_cache(values, width)

    selected_index =
      values
      |> pick_selected_index(last_state, root_attrs, cache)
      |> normalize_selected_index(cache)

    selected = selected_value(cache, selected_index)

    state =
      Map.merge(cache, %{
        values: values,
        selected: selected,
        selected_index: selected_index,
        offset: list_offset(root_attrs, last_state, cache, selected_index, scroll_padding),
        viewport_height: list_viewport_height(last_state),
        loop: loop,
        scroll_padding: scroll_padding,
        width: width
      })

    {:ok, state, state_change_requires_rerender: rendered_list_state_changed?(state, root_attrs)}
  end

  defp rendered_list_state_changed?(state, root_attrs) do
    rendered_selected = Map.get(root_attrs, :"list-rendered-selected")
    rendered_offset = Common.int_option(root_attrs, :"list-rendered-offset", 0)
    virtual? = Common.bool_option(root_attrs, :"list-virtual", false)
    windowed? = Common.bool_option(root_attrs, :"list-windowed", false)

    state.selected != rendered_selected or state.offset != rendered_offset or
      (virtual? and not windowed?)
  end

  defp list_viewport_height(last_state) do
    height =
      last_state
      |> Map.get(:__element__)
      |> Viewport.from_dimensions()
      |> Map.get(:viewport_height)

    if is_integer(height) and height > 0 do
      height
    else
      Map.get(last_state, :viewport_height)
    end
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
    index = max(length(state.values) - 1, 0)

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageDown", "element" => element}, state) do
    state = ensure_cache(state)
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    current_row = row_start(state, state.selected_index || 0)
    index = item_index_at_row(state, current_row + jump)

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    state = ensure_cache(state)
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    current_row = row_start(state, state.selected_index || 0)
    index = item_index_at_row(state, max(current_row - jump, 0))

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(
        _,
        %{
          "mouse" => %{"button" => "left", "action" => "press"},
          "row" => row,
          "element" => element
        },
        state
      )
      when is_integer(row) and row >= 0 do
    state = ensure_cache(state)

    case clicked_index_at_row(state, row + state.offset) do
      nil ->
        {:noreply, state}

      index ->
        state
        |> set_selection(index, element)
        |> maybe_change()
    end
  end

  def handle_event(
        _,
        %{"mouse" => %{"button" => "wheel_down"} = mouse, "element" => element},
        state
      ) do
    viewport = Viewport.from_dimensions(element)
    offset = Viewport.clamp_scroll_y(state.offset + Common.wheel_repeat(mouse), viewport)
    wheel_reply(state, offset)
  end

  def handle_event(
        _,
        %{"mouse" => %{"button" => "wheel_up"} = mouse, "element" => element},
        state
      ) do
    viewport = Viewport.from_dimensions(element)
    offset = Viewport.clamp_scroll_y(state.offset - Common.wheel_repeat(mouse), viewport)
    wheel_reply(state, offset)
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, state), do: Common.root_scroll_modifier(state)

  def handle_modifiers(:child, flags, state), do: Common.selected_modifier(flags, state)

  defp wheel_reply(%{offset: offset} = state, offset), do: {:bubble, state}
  defp wheel_reply(state, offset), do: {:noreply, %{state | offset: offset}}

  defp move_selection(%{values: []} = state, _delta, _element), do: state

  defp move_selection(state, delta, element) do
    state = ensure_cache(state)

    index =
      state
      |> next_index(delta)
      |> normalize_selected_index(state)

    set_selection(state, index, element)
  end

  defp set_selection(%{values: []} = state, _index, _element), do: state

  defp set_selection(state, index, element) do
    state = ensure_cache(state)
    index = normalize_selected_index(index, state)

    selected = selected_value(state, index)

    viewport = Viewport.from_dimensions(element)

    offset =
      if index do
        first = row_start(state, index)
        last = first + row_height(state, index) - 1

        Viewport.ensure_range_visible(state.offset, first, last, viewport,
          padding: state.scroll_padding
        )
      else
        Viewport.clamp_scroll_y(state.offset, viewport)
      end

    %{state | selected_index: index, selected: selected, offset: offset}
  end

  defp maybe_change(state), do: Common.change_reply(state)

  defp values_from_attrs(%{:"list-values" => values}, _children) when is_list(values) do
    values
  end

  defp values_from_attrs(_root_attrs, children) do
    children
    |> Enum.filter(&Map.has_key?(&1, :value))
    |> Enum.map(& &1.value)
  end

  defp list_offset(root_attrs, last_state, cache, selected_index, scroll_padding) do
    previous_offset =
      root_attrs
      |> Map.get(:"list-offset")
      |> Common.normalize_int(Map.get(last_state, :offset, 0))

    offset =
      if controlled_selection_changed?(root_attrs, last_state) do
        controlled_selection_offset(
          previous_offset,
          selected_index,
          last_state,
          cache,
          scroll_padding
        )
      else
        previous_offset
      end

    min(offset, max(cache.total_rows - 1, 0))
  end

  defp controlled_selection_offset(
         previous_offset,
         selected_index,
         %{__element__: element},
         cache,
         scroll_padding
       )
       when is_integer(selected_index) do
    viewport =
      element
      |> Viewport.from_dimensions()
      |> Map.put(:content_height, cache.total_rows)

    if viewport.viewport_height > 0 do
      first = row_start(cache, selected_index)
      last = first + row_height(cache, selected_index) - 1

      Viewport.ensure_range_visible(previous_offset, first, last, viewport,
        padding: scroll_padding
      )
    else
      row_start(cache, selected_index)
    end
  end

  defp controlled_selection_offset(_previous_offset, selected_index, _last_state, cache, _padding)
       when is_integer(selected_index),
       do: row_start(cache, selected_index)

  defp controlled_selection_offset(
         _previous_offset,
         _selected_index,
         _last_state,
         _cache,
         _padding
       ),
       do: 0

  defp controlled_selection_changed?(
         %{:"list-selected" => selected},
         %{selected: previous_selected}
       )
       when not is_nil(selected) and not is_nil(previous_selected),
       do: selected != previous_selected

  defp controlled_selection_changed?(_root_attrs, _last_state), do: false

  defp pick_selected_index(_values, last_state, root_attrs, cache) do
    selected = Map.get(last_state, :selected)
    controlled_selected = Map.get(root_attrs, :"list-selected")

    cond do
      not is_nil(controlled_selected) && Map.has_key?(cache.value_index, controlled_selected) ->
        Map.fetch!(cache.value_index, controlled_selected)

      not is_nil(selected) && Map.has_key?(cache.value_index, selected) ->
        Map.fetch!(cache.value_index, selected)

      match?(i when is_integer(i), Map.get(last_state, :selected_index)) ->
        Map.get(last_state, :selected_index)

      true ->
        case Map.fetch(root_attrs, :"list-initial-index") do
          {:ok, value} -> Common.normalize_int(value)
          :error -> nil
        end
    end
  end

  defp ensure_cache(%{count: count, value_tuple: value_tuple, row_starts: row_starts} = state)
       when is_integer(count) and is_tuple(value_tuple) and is_tuple(row_starts) do
    state
  end

  defp ensure_cache(%{values: values} = state) do
    Map.merge(build_cache(values, Map.get(state, :width, 0)), state)
  end

  defp build_cache(values, width) do
    {row_starts, row_heights, total_rows} =
      Enum.reduce(values, {[], [], 0}, fn value, {starts, heights, row} ->
        height = item_rows(value, width)
        {[row | starts], [height | heights], row + height}
      end)

    %{
      count: length(values),
      value_index: value_index(values),
      value_tuple: List.to_tuple(values),
      row_starts: row_starts |> Enum.reverse() |> List.to_tuple(),
      row_heights: row_heights |> Enum.reverse() |> List.to_tuple(),
      total_rows: total_rows
    }
  end

  defp value_index(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {value, index}, acc -> Map.put_new(acc, value, index) end)
  end

  defp normalize_selected_index(_index, %{count: 0}), do: nil

  defp normalize_selected_index(index, %{count: count}) when is_integer(index) do
    index
    |> max(0)
    |> min(count - 1)
  end

  defp normalize_selected_index(_index, _state), do: nil

  defp selected_value(_state, nil), do: nil
  defp selected_value(%{count: 0}, _index), do: nil

  defp selected_value(%{value_tuple: value_tuple}, index) when is_integer(index) do
    elem(value_tuple, index)
  end

  defp next_index(%{selected_index: nil, count: count}, delta) when delta >= 0 and count > 0,
    do: 0

  defp next_index(%{selected_index: nil, count: count}, _delta), do: max(count - 1, 0)

  defp next_index(%{selected_index: selected_index, count: count, loop: loop?}, delta) do
    max_index = max(count - 1, 0)
    next = selected_index + delta

    cond do
      loop? && next > max_index -> 0
      loop? && next < 0 -> max_index
      true -> next
    end
  end

  defp row_start(%{row_starts: row_starts}, index), do: elem(row_starts, index)
  defp row_height(%{row_heights: row_heights}, index), do: elem(row_heights, index)

  defp item_rows(_value, 0), do: 1

  defp item_rows(value, width),
    do: max(1, div(String.length(to_string(value)) + width - 1, width))

  defp item_index_at_row(%{count: 0}, _row), do: nil

  defp item_index_at_row(state, row) do
    row = max(row, 0)
    find_index_at_row(state, row, 0, state.count - 1)
  end

  defp find_index_at_row(state, _row, low, high) when low > high do
    low
    |> min(state.count - 1)
    |> max(0)
  end

  defp find_index_at_row(state, row, low, high) do
    mid = div(low + high, 2)
    start = row_start(state, mid)
    stop = start + row_height(state, mid)

    cond do
      row < start -> find_index_at_row(state, row, low, mid - 1)
      row < stop -> mid
      true -> find_index_at_row(state, row, mid + 1, high)
    end
  end

  defp clicked_index_at_row(state, row) do
    cond do
      state.count == 0 -> nil
      row < 0 -> nil
      row >= state.total_rows -> nil
      true -> item_index_at_row(state, row)
    end
  end
end
