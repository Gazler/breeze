defmodule Breeze.Inspector do
  @moduledoc false

  alias Breeze.Viewport

  @panel_height 11
  @max_preview_lines 2
  @max_render_preview_lines 3

  def panel_height, do: @panel_height

  def enabled?(state), do: config_source(state) not in [false, nil]

  def config(state) do
    case config_source(state) do
      config when is_list(config) -> config
      true -> []
      _ -> []
    end
  end

  def toggle_key(state), do: Keyword.get(config(state), :toggle_key, "F4")
  def move_key(state), do: Keyword.get(config(state), :move_key, "PageUp")

  def panel_position(state),
    do: inspector_field(state, :panel_position, :inspector_panel_position, :bottom)

  def picks_mouse?(state) do
    enabled?(state) and inspector_field(state, :visible?, :inspector_visible?, false)
  end

  def toggle(state) do
    visible? = not inspector_field(state, :visible?, :inspector_visible?, false)

    state
    |> put_inspector_field(:visible?, :inspector_visible?, visible?)
    |> put_inspector_field(
      :selected_id,
      :inspector_selected_id,
      if(visible?, do: inspector_field(state, :selected_id, :inspector_selected_id), else: nil)
    )
    |> put_inspector_field(:hovered_id, :inspector_hovered_id, nil)
    |> sync_selected_id()
  end

  def toggle_position(state) do
    next_position =
      case panel_position(state) do
        :top -> :bottom
        _ -> :top
      end

    put_inspector_field(state, :panel_position, :inspector_panel_position, next_position)
  end

  def hover_at(state, %{x: x, y: y}) do
    if inside_panel?(state, x, y) do
      state
    else
      put_inspector_field(
        state,
        :hovered_id,
        :inspector_hovered_id,
        state |> targets_at(x, y) |> List.first()
      )
    end
  end

  def select_at(state, %{x: x, y: y}) do
    if inside_panel?(state, x, y) do
      state
    else
      targets = targets_at(state, x, y)
      current = inspector_field(state, :selected_id, :inspector_selected_id)
      hovered = List.first(targets)

      id =
        if hovered == current do
          next_target(targets, current)
        else
          hovered
        end

      state
      |> put_inspector_field(:selected_id, :inspector_selected_id, id)
      |> put_inspector_field(:hovered_id, :inspector_hovered_id, id)
      |> sync_selected_id()
    end
  end

  def sync_selected_id(state) do
    selected_id =
      case inspector_field(state, :selected_id, :inspector_selected_id) do
        id when is_binary(id) ->
          if has_element?(state, id), do: id, else: fallback_selected_id(state)

        _ ->
          fallback_selected_id(state)
      end

    put_inspector_field(state, :selected_id, :inspector_selected_id, selected_id)
  end

  def snapshot(state, opts \\ []) do
    state = sync_selected_id(state)
    screen = Map.get(state.terminal, :size, %{width: 0, height: 0})
    selected_id = inspector_field(state, :selected_id, :inspector_selected_id)
    hovered_id = inspector_field(state, :hovered_id, :inspector_hovered_id)
    focusable_ids = focusable_ids(state)

    snapshot = %{
      enabled?: enabled?(state),
      visible?: inspector_field(state, :visible?, :inspector_visible?, false),
      selected_id: selected_id,
      hovered_id: hovered_id,
      focused: Map.get(state, :focused),
      root_view: Map.get(state, :view),
      theme: Map.get(state, :theme),
      source: %{
        node: node(),
        server_pid: self(),
        view_pid: Map.get(state, :view_pid)
      },
      screen: screen,
      last_render_at: Map.get(state, :last_render_at),
      last_interaction_at: Map.get(state, :last_interaction_at),
      counts: %{
        elements: map_size(rendered_field(state, :flags, :rendered_flags)),
        focusables: length(focusable_ids),
        mouse_targets: map_size(rendered_field(state, :mouse_targets, :rendered_mouse_targets)),
        children: map_size(Map.get(state, :children, %{}))
      },
      focus: %{
        active_scope: active_trapped_scope_id(state, focusable_ids),
        focusables: focusable_ids,
        focus_memory: Map.get(state, :focus_memory, %{})
      },
      render_tree?: not is_nil(rendered_field(state, :render_tree, :rendered_render_tree)),
      render_tree_kinds: render_tree_kinds(state),
      toggle_key: toggle_key(state),
      move_key: move_key(state),
      panel_position: panel_position(state),
      focused_entry: selected_snapshot(state, Map.get(state, :focused)),
      hovered: selected_snapshot(state, hovered_id),
      selected: selected_snapshot(state, selected_id)
    }

    if Keyword.get(opts, :timeline, true) and Breeze.Server.Timeline.enabled?(state) do
      Map.put(snapshot, :timeline, Breeze.Server.Timeline.snapshot(state))
    else
      snapshot
    end
  end

  def render_tree(state, opts \\ []) do
    tree = rendered_field(state, :render_tree, :rendered_render_tree)
    kind = normalize_render_tree_kind(Keyword.get(opts, :kind, :rendered))
    tree_meta = render_tree_meta_for_kind(state, kind)

    selected_id =
      Keyword.get(opts, :selected_id) ||
        inspector_field(state, :selected_id, :inspector_selected_id)

    limit = opts |> Keyword.get(:limit, 600) |> normalize_render_tree_limit()

    expanded =
      tree
      |> render_tree_expanded(tree_meta, Keyword.get(opts, :expanded, []), selected_id)
      |> Enum.uniq()

    {node, _remaining, truncated?} =
      prune_render_tree(tree, tree_meta, MapSet.new(expanded), limit)

    %{
      kind: kind,
      nodes: if(is_nil(node), do: [], else: [node]),
      selected_id: selected_id,
      expanded: expanded,
      limit: limit,
      truncated?: truncated?
    }
  end

  def overlays(state) do
    snapshot = snapshot(state)

    if snapshot.visible? do
      overlays =
        hover_overlays(snapshot.hovered, snapshot.selected_id) ++
          selected_overlays(snapshot.selected)

      if remote_delegate?() do
        overlays
      else
        overlays ++ panel_overlays(snapshot, state)
      end
    else
      []
    end
  end

  defp targets_at(state, x, y) do
    state
    |> rendered_field(:mouse_targets, :rendered_mouse_targets)
    |> Enum.filter(fn {_id, bounds} ->
      is_integer(bounds[:left]) and is_integer(bounds[:right]) and
        is_integer(bounds[:top]) and is_integer(bounds[:bottom]) and
        x - 1 >= bounds.left and x - 1 <= bounds.right and
        y - 1 >= bounds.top and y - 1 <= bounds.bottom
    end)
    |> Enum.sort_by(fn {_id, bounds} ->
      area = (bounds.right - bounds.left + 1) * (bounds.bottom - bounds.top + 1)
      {area, bounds.top, bounds.left}
    end)
    |> Enum.map(fn {target_id, _bounds} -> target_id end)
  end

  defp inside_panel?(state, x, y) do
    if remote_delegate?() do
      false
    else
      screen = Map.get(state.terminal, :size, %{width: 0, height: 0})
      row = y - 1
      col = x - 1

      panel_top =
        case panel_position(state) do
          :top -> 0
          _ -> max(screen.height - @panel_height, 0)
        end

      panel_bottom = panel_top + @panel_height - 1

      row >= panel_top and row <= panel_bottom and col >= 0 and col < screen.width
    end
  end

  defp next_target([], _current), do: nil
  defp next_target([target], _current), do: target

  defp next_target(targets, current) do
    case Enum.find_index(targets, &(&1 == current)) do
      nil -> hd(targets)
      index -> Enum.at(targets, index + 1) || hd(targets)
    end
  end

  defp selected_snapshot(_state, nil), do: nil

  defp selected_snapshot(state, id) do
    viewport = Map.get(rendered_field(state, :viewports, :rendered_viewports), id, %Viewport{})
    bounds = Map.get(rendered_field(state, :mouse_targets, :rendered_mouse_targets), id, %{})
    flags = normalize_flags(Map.get(rendered_field(state, :flags, :rendered_flags), id, []))
    actual_id = Map.get(flags, :id)
    box = Map.get(rendered_field(state, :boxes, :rendered_boxes), id)
    focus_meta = Map.get(rendered_field(state, :focus_meta, :rendered_focus_meta), id, %{})
    implicit_entry = Map.get(rendered_field(state, :implicit_state, :rendered_implicit_state), id)

    implicit_meta =
      Map.get(rendered_field(state, :implicit_meta, :rendered_implicit_meta), id, %{})

    {implicit_module, implicit_state} =
      case implicit_entry do
        {mod, implicit_state} -> {mod, implicit_state}
        _ -> {nil, nil}
      end

    fragment =
      case box do
        %BackBreeze.Box{} = box ->
          box
          |> BackBreeze.Box.render(terminal: state.terminal)
          |> Map.get(:content, "")

        _ ->
          ""
      end

    style = resolved_style(box, flags, state.theme)
    padding = padding(box, style)

    %{
      id: id,
      actual_id: actual_id,
      viewport: viewport,
      bounds: bounds,
      flags: flags,
      class: Map.get(flags, :class),
      component: Map.get(flags, :"breeze-component"),
      style_input: Map.get(flags, :style_input),
      style: style,
      focus_meta: focus_meta,
      focus_path: focus_path(state, focus_meta),
      remembered_focus: remembered_focus(state, focus_meta),
      implicit_module: implicit_module,
      implicit_state: implicit_state,
      implicit_meta: implicit_meta,
      fragment_preview: preview_fragment(fragment),
      fragment_render: render_fragment_preview(fragment),
      fragment_size: String.length(fragment),
      content_box: content_box(viewport, box, style),
      padding: padding,
      scroll: Map.get(flags, :scroll)
    }
  end

  defp normalize_flags(flags) when is_list(flags), do: Map.new(flags)
  defp normalize_flags(flags) when is_map(flags), do: flags
  defp normalize_flags(_flags), do: %{}

  defp fallback_selected_id(state) do
    cond do
      has_element?(state, Map.get(state, :focused)) ->
        Map.get(state, :focused)

      true ->
        flags = rendered_field(state, :flags, :rendered_flags)

        state
        |> rendered_field(:flags, :rendered_flags)
        |> Enum.sort_by(fn {key, _flags} -> key end)
        |> Enum.find_value(fn {key, flags} ->
          case Map.get(Map.new(flags), :id) do
            nil -> nil
            _ -> key
          end
        end) ||
          flags |> Map.keys() |> Enum.sort() |> List.first()
    end
  end

  defp has_element?(state, id) when is_binary(id) do
    Map.has_key?(rendered_field(state, :flags, :rendered_flags), id)
  end

  defp has_element?(_state, _id), do: false

  defp focusable_ids(state) do
    state
    |> rendered_field(:flags, :rendered_flags)
    |> Enum.filter(fn {_id, flags} ->
      Map.get(normalize_flags(flags), :focusable, false)
    end)
    |> Enum.map(fn {id, _flags} -> id end)
    |> Enum.sort()
  end

  defp normalize_render_tree_limit(limit) when is_integer(limit) and limit > 0 do
    min(limit, 2_000)
  end

  defp normalize_render_tree_limit(_limit), do: 600

  defp normalize_render_tree_kind(kind) when kind in [:code, "code"], do: :code
  defp normalize_render_tree_kind(_kind), do: :rendered

  defp render_tree_meta_for_kind(state, :code) do
    rendered_field(state, :code_tree_meta, :rendered_code_tree_meta)
  end

  defp render_tree_meta_for_kind(state, _kind) do
    rendered_field(state, :render_tree_meta, :rendered_render_tree_meta)
  end

  defp render_tree_kinds(state) do
    if is_nil(rendered_field(state, :render_tree, :rendered_render_tree)) do
      []
    else
      [:rendered, :code]
    end
  end

  defp render_tree_expanded(nil, _tree_meta, _expanded, _selected_id), do: []

  defp render_tree_expanded(tree, tree_meta, expanded, selected_id) do
    explicit = List.wrap(expanded)

    selected_path =
      tree
      |> render_tree_path(tree_meta, selected_id)
      |> Enum.drop(-1)

    expanded =
      case explicit ++ selected_path do
        [] -> expandable_tree_id(tree, tree_meta)
        ids -> ids
      end

    Enum.filter(expanded, &is_binary/1)
  end

  defp expandable_tree_id(%{idx: idx, children: [_ | _]}, tree_meta) do
    case Map.get(tree_meta, idx) do
      %{id: id} when is_binary(id) -> [id]
      _ -> []
    end
  end

  defp expandable_tree_id(_tree, _tree_meta), do: []

  defp render_tree_path(_tree, _tree_meta, selected_id) when not is_binary(selected_id), do: []

  defp render_tree_path(%{idx: idx, children: children}, tree_meta, selected_id)
       when is_list(children) do
    id = tree_meta |> Map.get(idx, %{}) |> Map.get(:id)

    if id == selected_id do
      [selected_id]
    else
      render_tree_child_path(id, children, tree_meta, selected_id)
    end
  end

  defp render_tree_path(_tree, _tree_meta, _selected_id), do: []

  defp render_tree_child_path(id, children, tree_meta, selected_id) do
    Enum.find_value(children, [], fn child ->
      case render_tree_path(child, tree_meta, selected_id) do
        [] -> nil
        path -> [id | path]
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp prune_render_tree(nil, _tree_meta, _expanded, limit), do: {nil, limit, false}

  defp prune_render_tree(_tree, _tree_meta, _expanded, remaining) when remaining <= 0,
    do: {nil, remaining, true}

  defp prune_render_tree(%{idx: idx, tag: tag} = tree, tree_meta, expanded, remaining) do
    meta = render_tree_node_meta(idx, tag, tree_meta)
    id = Map.get(meta, :id)
    children = Map.get(tree, :children, [])
    expandable? = children != []
    remaining = remaining - 1

    {children, remaining, truncated?} =
      if MapSet.member?(expanded, id) do
        prune_render_tree_children(children, tree_meta, expanded, remaining, [])
      else
        {[], remaining, false}
      end

    node = meta |> Map.put(:children, children) |> Map.put(:expandable?, expandable?)

    {node, remaining, truncated?}
  end

  defp prune_render_tree(_tree, _tree_meta, _expanded, remaining), do: {nil, remaining, false}

  defp render_tree_node_meta(idx, tag, tree_meta) do
    Map.get(tree_meta, idx, %{
      id: "__inspector__" <> Integer.to_string(idx),
      actual_id: nil,
      inspector_idx: idx,
      label: "<#{tag}>",
      label_parts: [%{text: "<#{tag}>", token: :tag}],
      tag: to_string(tag),
      flags: %{},
      bounds: %{}
    })
  end

  defp prune_render_tree_children([], _tree_meta, _expanded, remaining, acc) do
    {Enum.reverse(acc), remaining, false}
  end

  defp prune_render_tree_children(_children, _tree_meta, _expanded, remaining, acc)
       when remaining <= 0 do
    {Enum.reverse(acc), remaining, true}
  end

  defp prune_render_tree_children([child | rest], tree_meta, expanded, remaining, acc) do
    case prune_render_tree(child, tree_meta, expanded, remaining) do
      {nil, remaining, true} ->
        {Enum.reverse(acc), remaining, true}

      {nil, remaining, false} ->
        prune_render_tree_children(rest, tree_meta, expanded, remaining, acc)

      {node, remaining, true} ->
        {Enum.reverse([node | acc]), remaining, true}

      {node, remaining, false} ->
        prune_render_tree_children(rest, tree_meta, expanded, remaining, [node | acc])
    end
  end

  defp active_trapped_scope_id(state, focusable_ids) do
    focus_meta = rendered_field(state, :focus_meta, :rendered_focus_meta)

    focusable_ids
    |> Enum.flat_map(fn id ->
      case Map.get(focus_meta, id) do
        nil ->
          []

        meta ->
          trapped_ancestors =
            Enum.filter(Map.get(meta, :scope_path, []), &trapped_scope_id?(focus_meta, &1))

          if Map.get(meta, :focus_scope) == :trap do
            trapped_ancestors ++ [Map.get(meta, :id)]
          else
            trapped_ancestors
          end
      end
    end)
    |> List.last()
  end

  defp trapped_scope_id?(focus_meta, scope_id) do
    match?(%{focus_scope: :trap}, Map.get(focus_meta, scope_id))
  end

  defp focus_path(_state, %{} = focus_meta) do
    (Map.get(focus_meta, :scope_path, []) ++ [Map.get(focus_meta, :id)])
    |> Enum.reject(&is_nil/1)
  end

  defp focus_path(_state, _focus_meta), do: []

  defp remembered_focus(state, %{} = focus_meta) do
    focus_memory = Map.get(state, :focus_memory, %{})

    %{
      root: Map.get(focus_memory, :__root__),
      scope: Map.get(focus_memory, Map.get(focus_meta, :id)),
      trapped_scope:
        focus_meta
        |> Map.get(:scope_path, [])
        |> Enum.reverse()
        |> Enum.find(
          &trapped_scope_id?(rendered_field(state, :focus_meta, :rendered_focus_meta), &1)
        )
        |> then(&Map.get(focus_memory, &1))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp remembered_focus(_state, _focus_meta), do: %{}

  defp config_source(%{inspector_state: %{config: config}}), do: config
  defp config_source(state), do: Map.get(state, :inspector)

  defp inspector_field(state, field, legacy, default \\ nil)

  defp inspector_field(%{inspector_state: inspector}, field, _legacy, default) do
    Map.get(inspector, field, default)
  end

  defp inspector_field(state, _field, legacy, default) do
    Map.get(state, legacy, default)
  end

  defp put_inspector_field(
         %{inspector_state: %{__struct__: _struct} = inspector} = state,
         field,
         _legacy,
         value
       ) do
    %{state | inspector_state: struct!(inspector, [{field, value}])}
  end

  defp put_inspector_field(%{inspector_state: inspector} = state, field, _legacy, value) do
    %{state | inspector_state: Map.put(inspector, field, value)}
  end

  defp put_inspector_field(state, _field, legacy, value) do
    Map.put(state, legacy, value)
  end

  defp rendered_field(%{rendered: rendered}, field, _legacy) do
    Map.get(rendered, field, %{})
  end

  defp rendered_field(state, _field, legacy) do
    Map.get(state, legacy, %{})
  end

  defp content_box(viewport, %BackBreeze.Box{} = box, style) do
    style = merge_box_style(box, style)

    %{left: left_inset, right: right_inset, top: top_inset, bottom: bottom_inset} =
      inner_insets(style)

    %{
      left: viewport.left + left_inset,
      top: viewport.top + top_inset,
      width: max((viewport.width || 0) - left_inset - right_inset, 0),
      height: max(viewport.height - top_inset - bottom_inset, 0)
    }
  end

  defp content_box(viewport, _box, style) when is_map(style) do
    %{left: left_inset, right: right_inset, top: top_inset, bottom: bottom_inset} =
      inner_insets(style)

    %{
      left: viewport.left + left_inset,
      top: viewport.top + top_inset,
      width: max((viewport.width || 0) - left_inset - right_inset, 0),
      height: max(viewport.height - top_inset - bottom_inset, 0)
    }
  end

  defp content_box(viewport, _box, _style) do
    %{left: viewport.left, top: viewport.top, width: viewport.width || 0, height: viewport.height}
  end

  defp padding(%BackBreeze.Box{style: box_style}, style) do
    style = merge_box_style(%BackBreeze.Box{style: box_style}, style)

    %{
      top: style_value(style, :padding_top),
      right: style_value(style, :padding_right),
      bottom: style_value(style, :padding_bottom),
      left: style_value(style, :padding_left)
    }
  end

  defp padding(_box, style) when is_map(style) do
    %{
      top: style_value(style, :padding_top),
      right: style_value(style, :padding_right),
      bottom: style_value(style, :padding_bottom),
      left: style_value(style, :padding_left)
    }
  end

  defp padding(_box, _style), do: %{top: 0, right: 0, bottom: 0, left: 0}

  defp resolved_style(%BackBreeze.Box{style: style}, _flags, _theme) when is_map(style), do: style

  defp resolved_style(_box, flags, theme) do
    style_state =
      Breeze.Style.empty()
      |> maybe_put_class(Map.get(flags, :class))
      |> maybe_put_style(Map.get(flags, :style_input))

    style_state
    |> Breeze.Style.to_element(theme: theme, apply_theme_defaults: true)
    |> Map.get(:style, %{})
  end

  defp maybe_put_class(style_state, nil), do: style_state
  defp maybe_put_class(style_state, class), do: Breeze.Style.put_class(style_state, class)

  defp maybe_put_style(style_state, nil), do: style_state

  defp maybe_put_style(style_state, style_input),
    do: Breeze.Style.put_style(style_state, style_input)

  defp inner_insets(%BackBreeze.Box{style: %{border: border} = style}) do
    %{
      left: border_inset(border, :left) + style_value(style, :padding_left),
      right: border_inset(border, :right) + style_value(style, :padding_right),
      top: border_inset(border, :top) + style_value(style, :padding_top),
      bottom: border_inset(border, :bottom) + style_value(style, :padding_bottom)
    }
  end

  defp inner_insets(%BackBreeze.Box{style: style}) do
    %{
      left: style_value(style, :padding_left),
      right: style_value(style, :padding_right),
      top: style_value(style, :padding_top),
      bottom: style_value(style, :padding_bottom)
    }
  end

  defp inner_insets(%{border: border} = style) when is_map(style) do
    %{
      left: border_inset(border, :left) + style_value(style, :padding_left),
      right: border_inset(border, :right) + style_value(style, :padding_right),
      top: border_inset(border, :top) + style_value(style, :padding_top),
      bottom: border_inset(border, :bottom) + style_value(style, :padding_bottom)
    }
  end

  defp inner_insets(style) when is_map(style) do
    %{
      left: style_value(style, :padding_left),
      right: style_value(style, :padding_right),
      top: style_value(style, :padding_top),
      bottom: style_value(style, :padding_bottom)
    }
  end

  defp border_inset(border, side) do
    if Map.get(border, side), do: 1, else: 0
  end

  defp style_value(style, key) do
    case Map.get(style, key) do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  defp merge_box_style(%BackBreeze.Box{style: box_style}, resolved_style)
       when is_map(box_style) and is_map(resolved_style) do
    box_style =
      case box_style do
        %{__struct__: _struct} -> Map.from_struct(box_style)
        other -> other
      end

    Map.merge(resolved_style, box_style, fn _key, resolved, box ->
      case box do
        nil -> resolved
        _ -> box
      end
    end)
  end

  defp merge_box_style(_box, resolved_style), do: resolved_style

  defp selected_overlays(nil), do: []

  defp selected_overlays(%{bounds: bounds}) when bounds == %{}, do: []

  defp selected_overlays(%{bounds: bounds}) do
    highlight_overlays(bounds, "[", "]", "^", "v", "<", ">", 11)
  end

  defp hover_overlays(nil, _selected_id), do: []
  defp hover_overlays(%{id: id}, selected_id) when id == selected_id, do: []
  defp hover_overlays(%{bounds: bounds}, _selected_id) when bounds == %{}, do: []

  defp hover_overlays(%{bounds: bounds}, _selected_id) do
    highlight_overlays(bounds, "(", ")", ".", ".", ".", ".", 8)
  end

  defp highlight_overlays(
         bounds,
         left_char,
         right_char,
         top_char,
         bottom_char,
         mid_left_char,
         mid_right_char,
         background_color
       ) do
    left = bounds.left
    right = bounds.right
    top = bounds.top
    bottom = bounds.bottom
    mid_x = div(left + right, 2)
    mid_y = div(top + bottom, 2)

    [
      %{
        x: left,
        y: top,
        char: left_char,
        foreground_color: 0,
        background_color: background_color
      },
      %{
        x: right,
        y: top,
        char: right_char,
        foreground_color: 0,
        background_color: background_color
      },
      %{
        x: left,
        y: bottom,
        char: left_char,
        foreground_color: 0,
        background_color: background_color
      },
      %{
        x: right,
        y: bottom,
        char: right_char,
        foreground_color: 0,
        background_color: background_color
      },
      %{
        x: mid_x,
        y: top,
        char: top_char,
        foreground_color: 0,
        background_color: background_color
      },
      %{
        x: mid_x,
        y: bottom,
        char: bottom_char,
        foreground_color: 0,
        background_color: background_color
      },
      %{
        x: left,
        y: mid_y,
        char: mid_left_char,
        foreground_color: 0,
        background_color: background_color
      },
      %{
        x: right,
        y: mid_y,
        char: mid_right_char,
        foreground_color: 0,
        background_color: background_color
      }
    ]
    |> Enum.uniq_by(fn overlay -> {overlay.x, overlay.y} end)
  end

  defp panel_overlays(snapshot, state) do
    screen = snapshot.screen || %{width: 0, height: 0}

    start_row =
      case snapshot.panel_position do
        :top -> 0
        _ -> max(screen.height - @panel_height, 0)
      end

    content =
      Breeze.Renderer.render_to_string(
        Breeze.InspectorPanel,
        panel_assigns(snapshot),
        terminal: state.terminal,
        theme: snapshot.theme,
        theme_source: snapshot.theme,
        apply_theme_defaults: true
      )

    content
    |> String.split("\n", trim: false)
    |> Enum.take(@panel_height)
    |> Enum.with_index()
    |> Enum.map(fn {line, row_offset} ->
      %{x: 0, y: start_row + row_offset, content: line, clear_line: true, no_wrap: true}
    end)
  end

  defp panel_assigns(snapshot) do
    selected = snapshot.selected
    selected_style = (selected || %{})[:style] || %{}
    theme = snapshot.theme
    palette = panel_palette(snapshot)
    width = max(snapshot.screen.width, 1)
    muted = Breeze.Theme.color(theme, :muted) || palette.foreground

    border =
      case snapshot.panel_position do
        :top -> BackBreeze.Border.none() |> BackBreeze.Border.bottom()
        _ -> BackBreeze.Border.none() |> BackBreeze.Border.top()
      end

    %{
      root_style: %{
        width: width,
        height: @panel_height,
        border: border,
        border_color: palette.border,
        foreground_color: palette.foreground,
        background_color: palette.background,
        padding_left: 1,
        padding_right: 1
      },
      title_style: %{
        width: :full,
        bold: true,
        foreground_color: palette.border,
        background_color: palette.background
      },
      meta_style: %{
        width: :full,
        foreground_color: muted,
        background_color: palette.background
      },
      line_style: %{
        width: :full,
        foreground_color: palette.foreground,
        background_color: palette.background
      },
      color_text_style: %{
        width: max(width - 10, 1),
        foreground_color: palette.foreground,
        background_color: palette.background
      },
      swatch_label_style: %{
        foreground_color: muted,
        background_color: palette.background
      },
      fg_swatch_style: swatch_style(Map.get(selected_style, :foreground_color), palette),
      bg_swatch_style: swatch_style(Map.get(selected_style, :background_color), palette),
      show_fg_swatch?: not is_nil(Map.get(selected_style, :foreground_color)),
      show_bg_swatch?: not is_nil(Map.get(selected_style, :background_color)),
      title_text:
        truncate(
          "Inspector [#{snapshot.toggle_key}] root=#{inspect(snapshot.root_view)}",
          width - 2
        ),
      meta_text:
        truncate(
          "hovered=#{selected_label(snapshot.hovered, snapshot.hovered_id || "-")} selected=#{selected_label(selected, snapshot.selected_id || "-")} focused=#{snapshot.focused || "-"} dock=#{snapshot.panel_position} move=#{snapshot.move_key}",
          width - 2
        ),
      layout_text: truncate(layout_line(selected), width - 2),
      box_text: truncate(box_line(selected), width - 2),
      class_text: truncate(class_line(selected), width - 2),
      color_text: truncate(color_text(selected), width - 12),
      focus_text: truncate(focus_line(selected), width - 2),
      implicit_text: truncate(implicit_line(selected), width - 2),
      flags_text: truncate(flag_line(selected), width - 2),
      fragment_text: truncate(fragment_line(selected), width - 2)
    }
  end

  defp layout_line(nil), do: " layout: -"

  defp layout_line(%{viewport: viewport, bounds: bounds}) do
    " layout: left=#{viewport.left} top=#{viewport.top} width=#{viewport.width || 0} height=#{viewport.height} bounds=#{fmt_bounds(bounds)}"
  end

  defp box_line(nil), do: " box: -"

  defp box_line(%{viewport: viewport, content_box: content_box, padding: padding, scroll: scroll}) do
    " box: viewport=#{viewport.viewport_width || 0}x#{viewport.viewport_height} content=#{viewport.content_width || 0}x#{viewport.content_height} inner=#{content_box.width}x#{content_box.height} padding=#{fmt_padding(padding)} scroll=#{inspect(scroll || {0, 0})}"
  end

  defp class_line(nil), do: " class: -"
  defp class_line(%{class: nil}), do: " class: -"
  defp class_line(%{class: class}), do: " class: #{class}"

  defp color_text(nil), do: " colors: fg=- bg=-"

  defp color_text(%{style: style}) do
    " colors: fg=#{fmt_color(Map.get(style, :foreground_color))} bg=#{fmt_color(Map.get(style, :background_color))}"
  end

  defp focus_line(nil), do: " focus: -"

  defp focus_line(%{flags: flags, focus_meta: focus_meta}) do
    " focus: focusable=#{Map.get(flags, :focusable, false)} focused=#{Map.get(flags, :focused, false)} meta=#{compact_inspect(focus_meta, 120)}"
  end

  defp implicit_line(nil), do: " implicit: -"

  defp implicit_line(%{
         implicit_module: mod,
         implicit_state: implicit_state,
         implicit_meta: implicit_meta
       }) do
    " implicit: mod=#{inspect(mod)} state=#{compact_inspect(implicit_state, 80)} meta=#{compact_inspect(implicit_meta, 60)}"
  end

  defp flag_line(nil), do: " flags: -"
  defp flag_line(%{flags: flags}), do: " flags: #{compact_inspect(flags, 140)}"

  defp fragment_line(nil), do: " fragment: -"

  defp fragment_line(%{fragment_preview: fragment_preview}) do
    " fragment: #{fragment_preview}"
  end

  defp fmt_padding(%{top: top, right: right, bottom: bottom, left: left}) do
    "#{top}/#{right}/#{bottom}/#{left}"
  end

  defp fmt_color(nil), do: "-"
  defp fmt_color({r, g, b}), do: "rgb(#{r},#{g},#{b})"
  defp fmt_color(value), do: inspect(value)

  defp selected_label(nil, selected_id), do: selected_id

  defp selected_label(%{actual_id: actual_id, flags: flags}, selected_id) do
    cond do
      is_binary(actual_id) -> actual_id
      true -> "anon##{Map.get(flags, :__inspector_idx__, selected_id)}"
    end
  end

  defp preview_fragment(fragment) do
    fragment
    |> String.replace("\e", "\\e")
    |> String.split("\n")
    |> Enum.take(@max_preview_lines)
    |> Enum.join(" | ")
    |> truncate(140)
  end

  defp render_fragment_preview(fragment) do
    fragment
    |> String.split("\n")
    |> Enum.take(@max_render_preview_lines)
    |> Enum.join("\n")
  end

  defp compact_inspect(value, width) do
    value
    |> inspect(pretty: true, limit: 8, printable_limit: width)
    |> String.replace("\n", " ")
    |> String.replace(~r/\s+/, " ")
    |> truncate(width)
  end

  defp fmt_bounds(bounds) when bounds == %{}, do: "-"

  defp fmt_bounds(bounds) do
    "#{bounds.left},#{bounds.top}->#{bounds.right},#{bounds.bottom}"
  end

  defp panel_palette(snapshot) do
    theme = snapshot.theme
    selected_style = (snapshot.selected || %{})[:style] || %{}

    %{
      foreground:
        Breeze.Theme.color(theme, :text) || Map.get(selected_style, :foreground_color) ||
          Breeze.Theme.color(theme, :foreground_color) || 7,
      background:
        Breeze.Theme.color(theme, :panel) || Map.get(selected_style, :background_color) ||
          Breeze.Theme.color(theme, :background_color) || 0,
      border:
        Breeze.Theme.color(theme, :accent) || Breeze.Theme.color(theme, :border_color) ||
          Map.get(selected_style, :border_color) || 11
    }
  end

  defp swatch_style(nil, palette) do
    %{width: 4, foreground_color: palette.foreground, background_color: palette.background}
  end

  defp swatch_style(color, palette) do
    swatch_color = color || palette.background

    %{width: 4, foreground_color: swatch_color, background_color: palette.background}
  end

  defp remote_delegate?, do: Breeze.RemoteInspector.available?()

  defp truncate(text, width) when is_integer(width) and width > 3 do
    if String.length(text) > width do
      String.slice(text, 0, width - 3) <> "..."
    else
      text
    end
  end

  defp truncate(text, _width), do: text
end
