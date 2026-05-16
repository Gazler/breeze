defmodule Breeze.Implicit.Tree do
  @moduledoc false

  alias Breeze.Implicit.Common
  alias Breeze.Viewport

  @type row :: %{
          value: term(),
          parent: term() | nil,
          parents: list(term()),
          expandable?: boolean()
        }

  @type state :: %{
          rows: list(row()),
          values: list(),
          selected: term() | nil,
          selected_index: non_neg_integer() | nil,
          offset: non_neg_integer(),
          loop: boolean(),
          scroll_padding: non_neg_integer(),
          expanded: MapSet.t()
        }

  @spec init(list(map()), map()) :: state()
  def init(children, last_state), do: init(children, %{}, last_state)

  @spec init(list(map()), map(), map()) :: state()
  def init(children, root_attrs, last_state) do
    rows =
      children
      |> Enum.filter(&Map.get(&1, :"tree-node"))
      |> Enum.map(&row_from_child/1)

    expanded = expanded_values(root_attrs, last_state)
    values = visible_values(rows, expanded)

    loop =
      Common.bool_option(root_attrs, :"tree-loop", Map.get(last_state, :loop, true),
        numeric: true
      )

    scroll_padding =
      Common.int_option(
        root_attrs,
        :"tree-scroll-padding",
        Map.get(last_state, :scroll_padding, 0)
      )

    selected_index =
      values
      |> pick_selected_index(rows, expanded, last_state, root_attrs)
      |> Common.normalize_selected_index(values)

    selected = Common.selected_value(values, selected_index)

    %{
      rows: rows,
      values: values,
      selected: selected,
      selected_index: selected_index,
      offset: Common.normalize_int(Map.get(last_state, :offset, 0)),
      loop: loop,
      scroll_padding: scroll_padding,
      expanded: expanded
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

    state
    |> set_selection((state.selected_index || 0) + jump, element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => "PageUp", "element" => element}, state) do
    viewport = Viewport.from_dimensions(element)
    jump = max(viewport.viewport_height - 1, 1)

    state
    |> set_selection(max((state.selected_index || 0) - jump, 0), element)
    |> maybe_change()
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowRight", "l"] do
    case selected_row(state) do
      %{expandable?: true, value: value} = row ->
        if expanded?(state, value) do
          state
          |> select_first_child(row, element)
          |> maybe_change()
        else
          state
          |> expand_row(value)
          |> maybe_change()
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowLeft", "h"] do
    case selected_row(state) do
      %{expandable?: true, value: value} ->
        if expanded?(state, value) do
          state
          |> collapse_row(value)
          |> maybe_change()
        else
          state
          |> select_parent(element)
          |> maybe_change()
        end

      %{parent: parent} when not is_nil(parent) ->
        state
        |> select_parent(element)
        |> maybe_change()

      _ ->
        {:noreply, state}
    end
  end

  def handle_event(_, %{"key" => key}, state) when key in ["Enter", " "] do
    case selected_row(state) do
      %{expandable?: true, value: value} -> state |> toggle_row(value) |> maybe_change()
      _ -> {:noreply, state}
    end
  end

  def handle_event(
        _,
        %{
          "mouse" => %{button: :left, action: :press},
          "row" => row,
          "col" => col,
          "element" => element
        },
        state
      )
      when is_integer(row) and row >= 0 do
    with index when is_integer(index) <- row + state.offset,
         true <- index < length(state.values) do
      next_state = set_selection(state, index, element)
      selected = Enum.at(next_state.values, index)
      row = find_row(next_state.rows, selected)

      if row && row.expandable? && toggle_col?(row, col) do
        next_state
        |> toggle_row(selected)
        |> maybe_change()
      else
        maybe_change(next_state)
      end
    else
      _ -> {:noreply, state}
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

  def handle_modifiers(:child, flags, state) do
    cond do
      Keyword.get(flags, :"tree-node") ->
        tree_node_modifiers(flags, state)

      Keyword.get(flags, :"tree-node-part") ->
        tree_node_part_modifiers(flags, state)

      Keyword.get(flags, :"tree-collapsed-prefix") ->
        prefix_modifiers(flags, state, :collapsed)

      Keyword.get(flags, :"tree-expanded-prefix") ->
        prefix_modifiers(flags, state, :expanded)

      Keyword.get(flags, :"tree-leaf-prefix") ->
        prefix_modifiers(flags, state, :leaf)

      true ->
        []
    end
  end

  defp row_from_child(child) do
    %{
      value: Map.fetch!(child, :value),
      parent: Map.get(child, :"tree-parent"),
      parents: List.wrap(Map.get(child, :"tree-parents", [])),
      expandable?: Map.get(child, :"tree-expandable", false) in [true, "true", ""],
      depth: Common.normalize_int(Map.get(child, :"tree-depth", 0))
    }
  end

  defp expanded_values(root_attrs, last_state) do
    cond do
      Map.has_key?(root_attrs, :"tree-expanded") and not is_nil(root_attrs[:"tree-expanded"]) ->
        value_set(root_attrs[:"tree-expanded"])

      Map.has_key?(last_state, :expanded) ->
        value_set(last_state.expanded)

      true ->
        value_set(Map.get(root_attrs, :"tree-default-expanded", []))
    end
  end

  defp value_set(%MapSet{} = values), do: values

  defp value_set(values) when is_list(values), do: MapSet.new(values)

  defp value_set(values) when is_map(values) do
    values
    |> Enum.filter(fn {_key, value} -> value in [true, "true", "1", ""] end)
    |> Enum.map(fn {key, _value} -> key end)
    |> MapSet.new()
  end

  defp value_set(nil), do: MapSet.new()
  defp value_set(value), do: MapSet.new([value])

  defp visible_values(rows, expanded) do
    rows
    |> Enum.filter(&visible?(&1, expanded))
    |> Enum.map(& &1.value)
  end

  defp visible?(%{parents: parents}, expanded),
    do: Enum.all?(parents, &MapSet.member?(expanded, &1))

  defp pick_selected_index(values, rows, expanded, last_state, root_attrs) do
    controlled_selected = Map.get(root_attrs, :"tree-selected")
    selected = Map.get(last_state, :selected)

    cond do
      not is_nil(controlled_selected) ->
        index_or_visible_ancestor(values, rows, expanded, controlled_selected)

      not is_nil(selected) ->
        index_or_visible_ancestor(values, rows, expanded, selected)

      match?(i when is_integer(i), Map.get(last_state, :selected_index)) ->
        Map.get(last_state, :selected_index)

      true ->
        case Map.fetch(root_attrs, :"tree-initial-index") do
          {:ok, value} -> Common.normalize_int(value)
          :error -> nil
        end
    end
  end

  defp index_or_visible_ancestor(values, rows, expanded, value) do
    case Enum.find_index(values, &(&1 == value)) do
      nil ->
        rows
        |> find_row(value)
        |> visible_ancestor_value(rows, expanded)
        |> then(fn
          nil -> nil
          ancestor -> Enum.find_index(values, &(&1 == ancestor))
        end)

      index ->
        index
    end
  end

  defp visible_ancestor_value(nil, _rows, _expanded), do: nil

  defp visible_ancestor_value(%{parents: parents}, rows, expanded) do
    parents
    |> Enum.reverse()
    |> Enum.find(fn value ->
      rows
      |> find_row(value)
      |> case do
        nil -> false
        row -> visible?(row, expanded)
      end
    end)
  end

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
        Viewport.ensure_range_visible(state.offset, index, index, viewport,
          padding: state.scroll_padding
        )
      else
        Viewport.clamp_scroll_y(state.offset, viewport)
      end

    %{state | selected_index: index, selected: selected, offset: offset}
  end

  defp selected_row(%{selected: selected, rows: rows}), do: find_row(rows, selected)

  defp find_row(rows, value), do: Enum.find(rows, &(&1.value == value))

  defp expand_row(state, value),
    do: rebuild_visible(%{state | expanded: MapSet.put(state.expanded, value)})

  defp collapse_row(state, value),
    do: rebuild_visible(%{state | expanded: MapSet.delete(state.expanded, value)})

  defp toggle_row(state, value) do
    if expanded?(state, value), do: collapse_row(state, value), else: expand_row(state, value)
  end

  defp rebuild_visible(state) do
    values = visible_values(state.rows, state.expanded)
    selected_index = index_or_visible_ancestor(values, state.rows, state.expanded, state.selected)
    selected_index = Common.normalize_selected_index(selected_index, values)

    %{
      state
      | values: values,
        selected_index: selected_index,
        selected: Common.selected_value(values, selected_index)
    }
  end

  defp expanded?(state, value), do: MapSet.member?(state.expanded, value)

  defp select_first_child(state, row, element) do
    index =
      Enum.find_index(state.values, fn value ->
        case find_row(state.rows, value) do
          %{parent: parent} -> parent == row.value
          _ -> false
        end
      end)

    if index, do: set_selection(state, index, element), else: state
  end

  defp select_parent(state, element) do
    case selected_row(state) do
      %{parent: parent} when not is_nil(parent) ->
        case Enum.find_index(state.values, &(&1 == parent)) do
          nil -> state
          index -> set_selection(state, index, element)
        end

      _ ->
        state
    end
  end

  defp toggle_col?(%{depth: depth}, col) when is_integer(col) do
    col >= depth * 2 and col <= depth * 2 + 1
  end

  defp toggle_col?(_row, _col), do: false

  defp maybe_change(state) do
    {{:change,
      %{
        value: state.selected,
        index: state.selected_index,
        offset: state.offset,
        expanded: MapSet.to_list(state.expanded)
      }}, state}
  end

  defp tree_node_modifiers(flags, state) do
    value = Keyword.get(flags, :value)

    []
    |> then(fn modifiers ->
      if value in state.values, do: modifiers, else: [{:style, "hidden"} | modifiers]
    end)
    |> then(fn modifiers ->
      if not is_nil(value) and state.selected == value,
        do: [{:selected, true} | modifiers],
        else: modifiers
    end)
    |> Enum.reverse()
  end

  defp tree_node_part_modifiers(flags, state) do
    value = Keyword.get(flags, :selected_owner_value) || Keyword.get(flags, :value)

    if value in state.values, do: [], else: [{:style, "hidden"}]
  end

  defp prefix_modifiers(flags, state, kind) do
    value = Keyword.get(flags, :selected_owner_value) || Keyword.get(flags, :value)
    row = find_row(state.rows, value)

    visible? =
      value in state.values and
        case {kind, row} do
          {:collapsed, %{expandable?: true}} -> not expanded?(state, value)
          {:expanded, %{expandable?: true}} -> expanded?(state, value)
          {:leaf, %{expandable?: false}} -> true
          _ -> false
        end

    if visible?, do: [], else: [{:style, "hidden"}]
  end
end
