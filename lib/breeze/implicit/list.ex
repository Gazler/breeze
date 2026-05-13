defmodule Breeze.Implicit.List do
  @moduledoc false
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

  @type state :: %{
          values: list(),
          selected: term() | nil,
          selected_index: non_neg_integer() | nil,
          offset: non_neg_integer(),
          loop: boolean(),
          scroll_padding: non_neg_integer(),
          width: non_neg_integer()
        }

  @spec init(list(map()), map()) :: state()
  def init(children, last_state), do: init(children, %{}, last_state)

  @spec init(list(map()), map(), map()) :: state()
  def init(children, root_attrs, last_state) do
    values =
      children
      |> Enum.filter(&Map.has_key?(&1, :value))
      |> Enum.map(& &1.value)

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
      loop: loop,
      scroll_padding: scroll_padding,
      width: width
    }
  end

  @spec handle_event(term(), map(), state()) :: {:noreply, state()} | {{:change, map()}, state()}
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
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    current_row = rows_before(state.values, state.selected_index || 0, state.width)
    index = item_index_at_row(state.values, current_row + jump, state.width)

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)
    current_row = rows_before(state.values, state.selected_index || 0, state.width)
    index = item_index_at_row(state.values, max(current_row - jump, 0), state.width)

    state
    |> set_selection(index, element)
    |> maybe_change()
  end

  def handle_event(
        _,
        %{"mouse" => %{button: :left, action: :press}, "row" => row, "element" => element},
        state
      )
      when is_integer(row) and row >= 0 do
    case clicked_index_at_row(state.values, row + state.offset, state.width) do
      nil ->
        {:noreply, state}

      index ->
        state
        |> set_selection(index, element)
        |> maybe_change()
    end
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

  @spec handle_modifiers(:root | :child, keyword(), state()) :: keyword()
  def handle_modifiers(:root, _flags, state), do: Common.root_scroll_modifier(state)

  def handle_modifiers(:child, flags, state), do: Common.selected_modifier(flags, state)

  defp move_selection(%{values: []} = state, _delta, _element), do: state

  defp move_selection(state, delta, element) do
    index =
      state
      |> Common.next_index(delta)
      |> Common.normalize_selected_index(state.values)

    set_selection(state, index, element)
  end

  defp set_selection(%{values: []} = state, _index, _element), do: state

  defp set_selection(state, index, element) do
    values = state.values
    index = Common.normalize_selected_index(index, values)

    selected = Common.selected_value(values, index)

    viewport = Viewport.from_dimensions(element)

    offset =
      if index do
        first = rows_before(state.values, index, state.width)
        last = first + item_rows(Enum.at(state.values, index), state.width) - 1

        Viewport.ensure_range_visible(state.offset, first, last, viewport,
          padding: state.scroll_padding
        )
      else
        Viewport.clamp_scroll_y(state.offset, viewport)
      end

    %{state | selected_index: index, selected: selected, offset: offset}
  end

  defp maybe_change(state), do: Common.change_reply(state)

  defp pick_selected_index(values, last_state, root_attrs) do
    selected = Map.get(last_state, :selected)
    controlled_selected = Map.get(root_attrs, :"list-selected")

    cond do
      controlled_selected && Enum.member?(values, controlled_selected) ->
        Enum.find_index(values, &(&1 == controlled_selected))

      selected && Enum.member?(values, selected) ->
        Enum.find_index(values, &(&1 == selected))

      match?(i when is_integer(i), Map.get(last_state, :selected_index)) ->
        Map.get(last_state, :selected_index)

      true ->
        case Map.fetch(root_attrs, :"list-initial-index") do
          {:ok, value} -> Common.normalize_int(value)
          :error -> nil
        end
    end
  end

  defp item_rows(_value, 0), do: 1

  defp item_rows(value, width),
    do: max(1, div(String.length(to_string(value)) + width - 1, width))

  defp rows_before(values, index, width) do
    values |> Enum.take(index) |> Enum.reduce(0, fn v, acc -> acc + item_rows(v, width) end)
  end

  defp item_index_at_row(values, row, width) do
    {_, idx} =
      Enum.reduce_while(values, {0, 0}, fn v, {cur_row, idx} ->
        next_row = cur_row + item_rows(v, width)
        if next_row > row, do: {:halt, {cur_row, idx}}, else: {:cont, {next_row, idx + 1}}
      end)

    idx
  end

  defp clicked_index_at_row(values, row, width) do
    Enum.with_index(values)
    |> Enum.reduce_while({0, nil}, fn {value, idx}, {cur_row, _found} ->
      next_row = cur_row + item_rows(value, width)

      cond do
        row < cur_row ->
          {:halt, {cur_row, nil}}

        row < next_row ->
          {:halt, {cur_row, idx}}

        true ->
          {:cont, {next_row, nil}}
      end
    end)
    |> elem(1)
  end
end
