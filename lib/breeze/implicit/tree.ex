defmodule Breeze.Implicit.Tree do
  @moduledoc false

  @behaviour Breeze.Implicit

  alias Breeze.Implicit.Common
  alias Breeze.Viewport

  def init(children, root_attrs, last_state) do
    rows = rows_from_attrs(root_attrs, children)

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

    offset =
      if controlled_selection_changed?(root_attrs, last_state) do
        selected_index || 0
      else
        root_attrs
        |> Map.get(:"tree-offset")
        |> Common.normalize_int(Map.get(last_state, :offset, 0))
      end
      |> min(max(length(values) - 1, 0))

    {:ok,
     %{
       rows: rows,
       values: values,
       selected: selected,
       selected_index: selected_index,
       offset: offset,
       loop: loop,
       scroll_padding: scroll_padding,
       expanded: expanded
     }}
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
    state
    |> selected_row()
    |> handle_arrow_right(state, element)
  end

  def handle_event(_, %{"key" => key, "element" => element}, state)
      when key in ["ArrowLeft", "h"] do
    state
    |> selected_row()
    |> handle_arrow_left(state, element)
  end

  def handle_event(_, %{"key" => key}, state) when key in ["Enter", " "] do
    state
    |> selected_row()
    |> handle_toggle_key(state)
  end

  def handle_event(
        _,
        %{
          "mouse" => %{"button" => "left", "action" => "press"},
          "row" => row,
          "col" => col,
          "element" => element
        },
        state
      )
      when is_integer(row) and row >= 0 do
    handle_tree_click(row + state.offset, col, element, state)
  end

  def handle_event(
        _,
        %{"mouse" => %{"button" => "wheel_down"} = mouse, "element" => element},
        state
      ) do
    scroll_by_mouse(state, element, Common.wheel_repeat(mouse))
  end

  def handle_event(
        _,
        %{"mouse" => %{"button" => "wheel_up"} = mouse, "element" => element},
        state
      ) do
    scroll_by_mouse(state, element, -Common.wheel_repeat(mouse))
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, state), do: Common.root_scroll_modifier(state)

  def handle_modifiers(:child, flags, state) do
    flags
    |> child_modifier_flags()
    |> child_modifiers(flags, state)
  end

  defp child_modifier_flags(flags) do
    {
      Keyword.get(flags, :"tree-node"),
      Keyword.get(flags, :"tree-node-part"),
      Keyword.get(flags, :"tree-collapsed-prefix"),
      Keyword.get(flags, :"tree-expanded-prefix"),
      Keyword.get(flags, :"tree-leaf-prefix")
    }
  end

  defp child_modifiers({node_flag, _part, _collapsed, _expanded, _leaf}, flags, state)
       when node_flag not in [nil, false] do
    tree_node_modifiers(flags, state)
  end

  defp child_modifiers({_node, part_flag, _collapsed, _expanded, _leaf}, flags, state)
       when part_flag not in [nil, false] do
    tree_node_part_modifiers(flags, state)
  end

  defp child_modifiers({_node, _part, collapsed_flag, _expanded, _leaf}, flags, state)
       when collapsed_flag not in [nil, false] do
    prefix_modifiers(flags, state, :collapsed)
  end

  defp child_modifiers({_node, _part, _collapsed, expanded_flag, _leaf}, flags, state)
       when expanded_flag not in [nil, false] do
    prefix_modifiers(flags, state, :expanded)
  end

  defp child_modifiers({_node, _part, _collapsed, _expanded, leaf_flag}, flags, state)
       when leaf_flag not in [nil, false] do
    prefix_modifiers(flags, state, :leaf)
  end

  defp child_modifiers(_flags_tuple, _flags, _state), do: []

  defp rows_from_attrs(%{:"tree-rows" => rows}, _children) when is_list(rows) and rows != [] do
    rows
    |> Enum.filter(&is_map/1)
    |> Enum.map(&row_from_attrs/1)
  end

  defp rows_from_attrs(_root_attrs, children) do
    children
    |> Enum.filter(&Map.get(&1, :"tree-node"))
    |> Enum.map(&row_from_child/1)
  end

  defp row_from_attrs(row) when is_map(row) do
    %{
      value: Map.fetch!(row, :value),
      parent: Map.get(row, :parent),
      parents: List.wrap(Map.get(row, :parents, [])),
      expandable?: Map.get(row, :expandable?, false) in [true, "true", ""],
      depth: Common.normalize_int(Map.get(row, :depth, 0))
    }
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

  defp expanded_values(%{:"tree-expanded" => expanded}, _last_state) when not is_nil(expanded) do
    value_set(expanded)
  end

  defp expanded_values(_root_attrs, %{expanded: expanded}), do: value_set(expanded)

  defp expanded_values(root_attrs, _last_state) do
    value_set(Map.get(root_attrs, :"tree-default-expanded", []))
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
    root_attrs
    |> selected_index_source(last_state)
    |> selected_index_from_source(values, rows, expanded)
  end

  defp selected_index_source(%{:"tree-selected" => selected}, _last_state)
       when not is_nil(selected) do
    {:value, selected}
  end

  defp selected_index_source(_root_attrs, %{selected: selected}) when not is_nil(selected) do
    {:value, selected}
  end

  defp selected_index_source(_root_attrs, %{selected_index: index}) when is_integer(index) do
    {:index, index}
  end

  defp selected_index_source(%{:"tree-initial-index" => index}, _last_state) do
    {:index, Common.normalize_int(index)}
  end

  defp selected_index_source(_root_attrs, _last_state), do: nil

  defp controlled_selection_changed?(
         %{:"tree-selected" => selected},
         %{selected: previous_selected}
       )
       when not is_nil(selected) and not is_nil(previous_selected),
       do: selected != previous_selected

  defp controlled_selection_changed?(_root_attrs, _last_state), do: false

  defp selected_index_from_source({:value, value}, values, rows, expanded) do
    index_or_visible_ancestor(values, rows, expanded, value)
  end

  defp selected_index_from_source({:index, index}, _values, _rows, _expanded), do: index
  defp selected_index_from_source(nil, _values, _rows, _expanded), do: nil

  defp index_or_visible_ancestor(values, rows, expanded, value) do
    values
    |> Enum.find_index(&(&1 == value))
    |> index_or_visible_ancestor(values, rows, expanded, value)
  end

  defp index_or_visible_ancestor(nil, values, rows, expanded, value) do
    rows
    |> find_row(value)
    |> visible_ancestor_value(rows, expanded)
    |> visible_ancestor_index(values)
  end

  defp index_or_visible_ancestor(index, _values, _rows, _expanded, _value), do: index

  defp visible_ancestor_index(nil, _values), do: nil
  defp visible_ancestor_index(ancestor, values), do: Enum.find_index(values, &(&1 == ancestor))

  defp visible_ancestor_value(nil, _rows, _expanded), do: nil

  defp visible_ancestor_value(%{parents: parents}, rows, expanded) do
    parents
    |> Enum.reverse()
    |> Enum.find(&visible_row_value?(&1, rows, expanded))
  end

  defp visible_row_value?(value, rows, expanded) do
    rows
    |> find_row(value)
    |> visible_row?(expanded)
  end

  defp visible_row?(nil, _expanded), do: false
  defp visible_row?(row, expanded), do: visible?(row, expanded)

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

    offset = selection_offset(index, state, viewport)

    %{state | selected_index: index, selected: selected, offset: offset}
  end

  defp selection_offset(nil, state, viewport), do: Viewport.clamp_scroll_y(state.offset, viewport)

  defp selection_offset(index, state, viewport) do
    Viewport.ensure_range_visible(state.offset, index, index, viewport,
      padding: state.scroll_padding
    )
  end

  defp selected_row(%{selected: selected, rows: rows}), do: find_row(rows, selected)

  defp find_row(rows, value), do: Enum.find(rows, &(&1.value == value))

  defp handle_arrow_right(%{expandable?: true, value: value} = row, state, element) do
    state
    |> right_arrow_state(row, expanded?(state, value), element)
    |> maybe_change()
  end

  defp handle_arrow_right(_row, state, _element), do: {:noreply, state}

  defp right_arrow_state(state, row, true, element), do: select_first_child(state, row, element)
  defp right_arrow_state(state, %{value: value}, false, _element), do: expand_row(state, value)

  defp handle_arrow_left(%{expandable?: true, value: value}, state, element) do
    state
    |> left_arrow_state(value, expanded?(state, value), element)
    |> maybe_change()
  end

  defp handle_arrow_left(%{parent: parent}, state, element) when not is_nil(parent) do
    state
    |> select_parent(element)
    |> maybe_change()
  end

  defp handle_arrow_left(_row, state, _element), do: {:noreply, state}

  defp left_arrow_state(state, value, true, _element), do: collapse_row(state, value)
  defp left_arrow_state(state, _value, false, element), do: select_parent(state, element)

  defp handle_toggle_key(%{expandable?: true, value: value}, state) do
    state
    |> toggle_row(value)
    |> maybe_change()
  end

  defp handle_toggle_key(_row, state), do: {:noreply, state}

  defp handle_tree_click(index, col, element, %{values: values} = state)
       when is_integer(index) and index >= 0 and index < length(values) do
    next_state = set_selection(state, index, element)
    selected = Enum.at(next_state.values, index)

    next_state.rows
    |> find_row(selected)
    |> handle_tree_click_row(selected, col, next_state)
  end

  defp handle_tree_click(_index, _col, _element, state), do: {:noreply, state}

  defp handle_tree_click_row(%{expandable?: true} = row, selected, col, state) do
    row
    |> toggle_col?(col)
    |> handle_tree_click_toggle(selected, state)
  end

  defp handle_tree_click_row(_row, _selected, _col, state), do: maybe_change(state)

  defp handle_tree_click_toggle(true, selected, state) do
    state
    |> toggle_row(selected)
    |> maybe_change()
  end

  defp handle_tree_click_toggle(false, _selected, state), do: maybe_change(state)

  defp scroll_by_mouse(state, element, delta) do
    viewport = Viewport.from_dimensions(element)
    offset = Viewport.clamp_scroll_y(state.offset + delta, viewport)

    {:noreply, Map.put(state, :offset, offset)}
  end

  defp expand_row(state, value),
    do: rebuild_visible(%{state | expanded: MapSet.put(state.expanded, value)})

  defp collapse_row(state, value),
    do: rebuild_visible(%{state | expanded: MapSet.delete(state.expanded, value)})

  defp toggle_row(state, value), do: toggle_row(state, value, expanded?(state, value))

  defp toggle_row(state, value, true), do: collapse_row(state, value)
  defp toggle_row(state, value, false), do: expand_row(state, value)

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

  defp select_first_child(state, %{value: parent}, element) do
    state.values
    |> Enum.find_index(&child_row_value?(state, &1, parent))
    |> select_index(state, element)
  end

  defp child_row_value?(state, value, parent) do
    state.rows
    |> find_row(value)
    |> child_row?(parent)
  end

  defp child_row?(%{parent: row_parent}, parent), do: row_parent == parent
  defp child_row?(_row, _parent), do: false

  defp select_parent(state, element) do
    state
    |> selected_row()
    |> select_parent(state, element)
  end

  defp select_parent(%{parent: parent}, state, element) when not is_nil(parent) do
    state.values
    |> Enum.find_index(&(&1 == parent))
    |> select_index(state, element)
  end

  defp select_parent(_row, state, _element), do: state

  defp select_index(nil, state, _element), do: state
  defp select_index(index, state, element), do: set_selection(state, index, element)

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

    hidden_tree_node_modifiers(value, state) ++
      selected_tree_node_modifiers(value, state)
  end

  defp hidden_tree_node_modifiers(value, state) do
    value
    |> visible_value?(state)
    |> hidden_modifiers()
  end

  defp selected_tree_node_modifiers(nil, _state), do: []

  defp selected_tree_node_modifiers(value, %{selected: selected}) when value == selected do
    [selected: true]
  end

  defp selected_tree_node_modifiers(_value, _state), do: []

  defp tree_node_part_modifiers(flags, state) do
    flags
    |> tree_part_value()
    |> visible_value?(state)
    |> hidden_modifiers()
  end

  defp tree_part_value(flags) do
    Keyword.get(flags, :selected_owner_value) || Keyword.get(flags, :value)
  end

  defp prefix_modifiers(flags, state, kind) do
    value = tree_part_value(flags)

    state.rows
    |> find_row(value)
    |> prefix_visible?(kind, value, state)
    |> hidden_modifiers()
  end

  defp prefix_visible?(row, kind, value, state) do
    value
    |> visible_value?(state)
    |> prefix_visible?(row, kind, value, state)
  end

  defp prefix_visible?(false, _row, _kind, _value, _state), do: false

  defp prefix_visible?(true, %{expandable?: true}, :collapsed, value, state) do
    not expanded?(state, value)
  end

  defp prefix_visible?(true, %{expandable?: true}, :expanded, value, state) do
    expanded?(state, value)
  end

  defp prefix_visible?(true, %{expandable?: false}, :leaf, _value, _state), do: true
  defp prefix_visible?(_visible, _row, _kind, _value, _state), do: false

  defp visible_value?(value, %{values: values}), do: value in values

  defp hidden_modifiers(true), do: []
  defp hidden_modifiers(false), do: [style: "hidden"]
end
