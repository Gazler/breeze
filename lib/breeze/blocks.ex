defmodule Breeze.Blocks do
  @moduledoc """
  Reusable built-in components for Breeze views.

  Import this module in your view to use the provided components:

      defmodule MyView do
        use Breeze.View
        import Breeze.Blocks
        ...
      end

  ## Class merging

  All components expose a `class` attribute (and where applicable an
  `item_class` attribute) that are merged with the component's defaults using
  `merge_class/2`. Style tokens are grouped by their *property key*, everything
  before the last `-` segment, so an override of `"width-32"` replaces the
  default `"width-24"` while leaving other properties intact (including `focus:`
  prefixes).
  """

  use Breeze.View
  alias BackBreeze.Ucwidth

  attr :keybindings, :list, default: []
  attr :class, :string, default: nil

  def keybinding_bar(assigns) do
    assigns =
      assign(assigns,
        parts:
          Map.get(assigns, :keybindings, [])
          |> Enum.with_index()
          |> Enum.flat_map(fn {%{key: key, label: label}, index} ->
            key = to_string(key)
            label = to_string(label || key)
            separator? = index < length(Map.get(assigns, :keybindings, [])) - 1

            [
              %{class: "text-accent bold", content: key},
              %{class: nil, content: " " <> label}
            ] ++ if(separator?, do: [%{class: nil, content: "  "}], else: [])
          end)
      )

    ~H"""
    <box
      :if={@parts != []}
      class={@class || "inline width-full overflow-hidden padding-left-2 padding-right-1"}
    >
      <box :for={%{class: class, content: content} <- @parts} class={class}>{content}</box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :loop, :boolean, default: true
  attr :variant, :string, default: nil
  attr :"selected-indicator", :string, default: ">"
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :item_class, :string, default: nil
  attr :item_style, :any, default: nil
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def list(assigns) do
    selected_indicator = Map.get(assigns, :"selected-indicator", ">") || ">"
    selected_indicator_width = max(Ucwidth.width(selected_indicator), 1)

    root_defaults =
      "border width-full height-8 overflow-scroll scrollbar-arrows focus:border-primary focus:scrollbar-primary"

    root_defaults =
      if assigns[:variant] == "muted" do
        root_defaults <> " mute-scrollbar-40 focus:mute-scrollbar-0"
      else
        root_defaults
      end

    item_visual_defaults =
      merge_class(
        "selected:bg-primary selected:text-bg",
        list_variant_item_class(Map.get(assigns, :variant))
      )

    assigns =
      assigns
      |> assign(selected_indicator: selected_indicator)
      |> assign(selected_indicator_width: selected_indicator_width)
      |> assign(item_visual_defaults: item_visual_defaults)
      |> assign(class: merge_class(root_defaults, class_override(assigns)))
      |> assign(
        item_class:
          merge_class(
            "inline overflow-hidden padding-left-#{selected_indicator_width} selected:padding-left-0 width-full",
            merge_class(item_visual_defaults, class_override(assigns, :item_class, :item_style))
          )
      )
      |> assign(
        marker_class:
          merge_class(
            item_visual_defaults,
            "hidden selected:width-#{selected_indicator_width} overflow-hidden"
          )
      )

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.List}
      list-loop={@loop}
      list-scroll-padding={1}
      focusable
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      <box
        :for={item <- @item}
        value={item.value}
        focus-with-owner
        class="inline"
        style={Breeze.Blocks.inline_style(assigns, :item_class, :item_style)}
      >
        <box selected-with-owner class={@marker_class}>{@selected_indicator}</box>
        <box selected-with-owner class={@item_class}>{render_slot(item, %{})}</box>
      </box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :selected, :string, default: nil
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :menu_class, :string, default: nil
  attr :menu_style, :any, default: nil
  attr :item_class, :string, default: nil
  attr :item_style, :any, default: nil
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def dropdown(assigns) do
    trigger_chrome_width = 4
    minimum_width = 10

    items_with_labels =
      Enum.map(assigns.item, fn item ->
        {item, render_slot(item, %{})}
      end)

    selected_label =
      case Enum.find(items_with_labels, fn {item, _label} ->
             Map.get(item, :value) == assigns[:selected]
           end) do
        {_item, label} -> label
        nil -> to_string(assigns[:selected] || "")
      end

    width =
      case Breeze.Style.resolve_dimensions(assigns[:class], assigns[:style]).width do
        resolved when is_integer(resolved) ->
          resolved

        :full ->
          :full

        _ ->
          candidate_widths =
            Enum.map(items_with_labels, fn {_item, label} ->
              String.length(label) + trigger_chrome_width
            end)

          [String.length(selected_label) + trigger_chrome_width, minimum_width | candidate_widths]
          |> Enum.max()
      end

    menu_width = width
    menu_height = max(length(items_with_labels), 1)
    trigger_content = build_dropdown_trigger(selected_label, width)

    trigger_visual_class =
      merge_class(
        "bg-primary text-bg bold focus:inverse",
        class_override(assigns)
      )

    assigns =
      assigns
      |> assign(trigger_visual_class: trigger_visual_class)
      |> assign(selected_label: selected_label)
      |> assign(width: width)
      |> assign(menu_width: menu_width)
      |> assign(menu_height: menu_height)
      |> assign(trigger_content: trigger_content)
      |> assign(
        trigger_class:
          merge_class(
            "#{size_class("width", width)} height-1 padding-right-1 #{trigger_visual_class}",
            nil
          )
      )
      |> assign(
        menu_class:
          merge_class(
            "bg-primary text-background",
            class_override(assigns, :menu_class, :menu_style)
          )
      )
      |> assign(
        item_class:
          merge_class(
            "#{size_class("width", menu_width)} bg-primary text-background selected:inverse",
            class_override(assigns, :item_class, :item_style)
          )
      )

    assigns =
      assign(assigns,
        item_styles:
          items_with_labels
          |> Enum.with_index()
          |> Enum.map(fn {{item, _label}, index} ->
            {item, index, assigns.item_class}
          end)
      )

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.Dropdown}
      focusable
      dropdown-selected={@selected}
      dropdown-menu-width={@menu_width}
      dropdown-menu-height={@menu_height}
      class={@trigger_class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      {@trigger_content}
      <box dropdown-indicator-closed class={@trigger_visual_class}>▼</box>
      <box dropdown-indicator-open class={@trigger_visual_class}>▲</box>
      <box
        dropdown-frame
        class={@menu_class}
        style={Breeze.Blocks.inline_style(assigns, :menu_class, :menu_style)}
      >
      </box>
      <box
        :for={{item, index, item_style} <- @item_styles}
        dropdown-item
        dropdown-item-index={index}
        value={item.value}
        class={item_style}
        style={Breeze.Blocks.inline_style(assigns, :item_class, :item_style)}
      >
        {render_slot(item, %{})}
      </box>
    </box>
    """
  end

  defp build_dropdown_trigger(label, width) when is_integer(width) do
    inner_width = max(width - 2, 0)
    padded = String.pad_trailing(to_string(label), inner_width) |> String.slice(0, inner_width)
    " " <> padded
  end

  defp build_dropdown_trigger(label, _width), do: " " <> to_string(label)

  defp list_variant_item_class("muted") do
    "mute-text-20 selected:mute-bg-20 focus:selected:mute-bg-0 focus:mute-text-0 selected:text-bg focus:selected:bg-primary focus:selected:mute-text-0"
  end

  defp list_variant_item_class("accent") do
    "selected:bg-primary selected:text-bg focus:selected:bg-accent"
  end

  defp list_variant_item_class(_), do: nil

  attr :id, :string, required: true
  attr :nodes, :list, default: []
  attr :selected, :any, default: nil
  attr :expanded, :any, default: nil
  attr :default_expanded, :any, default: []
  attr :loop, :boolean, default: true
  attr :virtual, :boolean, default: false
  attr :virtual_overscan, :integer, default: 24
  attr :offset, :integer, default: nil
  attr :virtual_window, :integer, default: nil
  attr :collapsed_prefix, :string, default: ">"
  attr :expanded_prefix, :string, default: "⌄"
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :rest, :global

  slot :item
  slot :empty

  def tree(assigns) do
    visible_expanded = rendered_tree_expanded(assigns)
    controlled_expanded? = not is_nil(visible_expanded)
    rows = normalize_tree_rows(assigns.nodes, visible_expanded, assigns)

    prefix_width =
      [
        assigns.collapsed_prefix,
        assigns.expanded_prefix,
        " "
      ]
      |> Enum.map(&tree_prefix_width/1)
      |> Enum.max()
      |> max(1)

    item_visual_defaults = "selected:bg-primary selected:text-bg"

    assigns =
      assigns
      |> assign(rows: rows)
      |> assign(implicit_rows: implicit_tree_rows(rows))
      |> assign(controlled_expanded?: controlled_expanded?)
      |> assign(prefix_width: prefix_width)
      |> assign(
        class:
          merge_class(
            "border width-full height-8 overflow-scroll scrollbar-arrows focus:border-primary focus:scrollbar-primary",
            class_override(assigns)
          )
      )
      |> assign(
        item_class:
          merge_class(
            "inline width-full height-1 overflow-hidden",
            item_visual_defaults
          )
      )
      |> assign(prefix_cell_class: "inline width-#{prefix_width} height-1 overflow-hidden")
      |> assign(label_class: merge_class("inline height-1 overflow-hidden", item_visual_defaults))

    {render_rows, top_spacer, bottom_spacer, windowed?} = tree_render_window(rows, assigns)

    assigns =
      assigns
      |> assign(render_rows: render_rows)
      |> assign(top_spacer: top_spacer)
      |> assign(bottom_spacer: bottom_spacer)
      |> assign(tree_offset: if(windowed?, do: top_spacer, else: assigns.offset))

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.Tree}
      tree-loop={@loop}
      tree-selected={@selected}
      tree-expanded={@expanded}
      tree-default-expanded={@default_expanded}
      tree-offset={@tree_offset}
      tree-rows={@implicit_rows}
      tree-scroll-padding={1}
      focusable
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      <box :if={@rows == [] and @empty != []} class="width-full height-1 text-muted">
        {render_slot(@empty)}
      </box>
      <box :if={@top_spacer > 0} class={"width-full height-#{@top_spacer} overflow-hidden"}>
      </box>
      <box
        :for={row <- @render_rows}
        value={row.value}
        tree-node
        tree-depth={row.depth}
        tree-parent={row.parent}
        tree-parents={row.parents}
        tree-expandable={row.expandable?}
        focus-with-owner
        class={@item_class}
      >
        <box
          :if={row.indent_width > 0}
          tree-node-part
          selected-with-owner
          class={"inline width-#{row.indent_width} height-1 overflow-hidden"}
        >
        </box>
        <box
          :if={@controlled_expanded?}
          tree-node-part
          selected-with-owner
          class={@prefix_cell_class}
        >
          {row.prefix}
        </box>
        <box
          :if={!@controlled_expanded?}
          tree-node-part
          selected-with-owner
          class={@prefix_cell_class}
        >
          <box tree-collapsed-prefix selected-with-owner class={@prefix_cell_class}>
            {@collapsed_prefix}
          </box>
          <box tree-expanded-prefix selected-with-owner class={@prefix_cell_class}>
            {@expanded_prefix}
          </box>
          <box tree-leaf-prefix selected-with-owner class={@prefix_cell_class}>{" "}</box>
        </box>
        <box :if={@item == []} tree-node-part selected-with-owner class={@label_class}>
          {row.label}
        </box>
        <box :if={@item != []} tree-node-part selected-with-owner class={@label_class}>
          {render_slot(@item, row)}
        </box>
      </box>
      <box :if={@bottom_spacer > 0} class={"width-full height-#{@bottom_spacer} overflow-hidden"}>
      </box>
    </box>
    """
  end

  defp tree_render_window(rows, assigns) do
    total = length(rows)

    with window_size when is_integer(window_size) <-
           tree_window_size(assigns),
         offset when is_integer(offset) <- tree_window_offset(rows, assigns, window_size),
         true <- total > window_size do
      render_rows = Enum.slice(rows, offset, window_size)
      bottom_spacer = max(total - offset - length(render_rows), 0)

      {render_rows, offset, bottom_spacer, true}
    else
      _ -> {rows, 0, 0, false}
    end
  end

  defp tree_window_size(assigns) do
    explicit = normalize_tree_window_size(assigns.virtual_window)

    cond do
      is_integer(explicit) ->
        explicit

      assigns.virtual in [true, "true", "1", ""] ->
        inferred_tree_window_size(assigns)

      true ->
        nil
    end
  end

  defp inferred_tree_window_size(assigns) do
    overscan = normalize_tree_overscan(assigns.virtual_overscan)

    height =
      Breeze.Style.resolve_dimensions(Map.get(assigns, :class), inline_style(assigns)).height

    visible_rows =
      case height do
        height when is_integer(height) and height > 0 ->
          height

        height when height in [:full, :screen] ->
          assigns
          |> caller_terminal_height()
          |> case do
            height when is_integer(height) and height > 0 -> height
            _ -> nil
          end

        _ ->
          nil
      end

    if is_integer(visible_rows), do: max(visible_rows + overscan, 1)
  end

  defp normalize_tree_overscan(value) when is_integer(value), do: max(value, 0)

  defp normalize_tree_overscan(value) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> max(value, 0)
      _ -> 24
    end
  end

  defp normalize_tree_overscan(_value), do: 24

  defp caller_terminal_height(assigns) do
    get_in(assigns, [:__breeze_caller_assigns__, :breeze, :terminal, :height])
  end

  defp normalize_tree_window_size(size) when is_integer(size) and size > 0, do: size

  defp normalize_tree_window_size(size) when is_binary(size) do
    case Integer.parse(size) do
      {size, ""} when size > 0 -> size
      _ -> nil
    end
  end

  defp normalize_tree_window_size(_size), do: nil

  defp tree_window_offset(_rows, _assigns, window_size) when window_size <= 0, do: nil

  defp tree_window_offset(rows, assigns, window_size) do
    total = length(rows)

    assigns
    |> explicit_or_implicit_tree_offset()
    |> case do
      offset when is_integer(offset) ->
        normalize_tree_window_offset(offset, total)

      _ ->
        selected = explicit_or_implicit_tree_selected(assigns)
        selected_index = Enum.find_index(rows, &(&1.value == selected))

        case selected_index do
          index when is_integer(index) ->
            normalize_tree_window_offset(index - div(window_size, 2), total)

          _ ->
            0
        end
    end
  end

  defp normalize_tree_window_offset(_offset, total) when total <= 0, do: nil

  defp normalize_tree_window_offset(offset, total) when is_integer(offset) do
    offset
    |> max(0)
    |> min(total - 1)
  end

  defp normalize_tree_window_offset(offset, total) when is_binary(offset) do
    case Integer.parse(offset) do
      {offset, ""} -> normalize_tree_window_offset(offset, total)
      _ -> nil
    end
  end

  defp normalize_tree_window_offset(_offset, _total), do: nil

  defp explicit_or_implicit_tree_offset(assigns) do
    case assigns.offset do
      nil -> get_in(tree_implicit_state(assigns), [:offset])
      offset -> offset
    end
  end

  defp explicit_or_implicit_tree_selected(assigns) do
    case assigns.selected do
      nil -> get_in(tree_implicit_state(assigns), [:selected])
      selected -> selected
    end
  end

  defp implicit_tree_rows(rows) do
    Enum.map(rows, fn row ->
      %{
        value: row.value,
        parent: row.parent,
        parents: row.parents,
        expandable?: row.expandable?,
        depth: row.depth
      }
    end)
  end

  defp normalize_tree_rows(nodes, visible_expanded, assigns) do
    nodes
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, index} ->
      normalize_tree_node(node, assigns, visible_expanded, nil, [], 0, [index])
    end)
  end

  defp normalize_tree_node(node, assigns, visible_expanded, parent, parents, depth, path) do
    value = tree_node_value(node, path)
    label = tree_node_label(node, value)
    children = tree_node_children(node)
    expandable? = tree_node_expandable(node, children != [])

    row = %{
      value: value,
      label: label,
      node: node,
      prefix: tree_row_prefix(value, expandable?, visible_expanded, assigns),
      parent: parent,
      parents: parents,
      depth: depth,
      indent_width: depth * 2,
      expandable?: expandable?
    }

    child_rows =
      if render_tree_children?(visible_expanded, value) do
        children
        |> Enum.with_index()
        |> Enum.flat_map(fn {child, index} ->
          normalize_tree_node(
            child,
            assigns,
            visible_expanded,
            value,
            parents ++ [value],
            depth + 1,
            path ++ [index]
          )
        end)
      else
        []
      end

    [row | child_rows]
  end

  defp tree_node_value(node, path), do: tree_node_lookup(node, :id, path)

  defp tree_node_label(node, value) do
    node
    |> tree_node_lookup(:label, value)
    |> normalize_tree_label()
  end

  defp normalize_tree_label(%{__struct__: BackBreeze.VirtualText} = value), do: value
  defp normalize_tree_label([%{__struct__: BackBreeze.TextSpan} | _rest] = value), do: value
  defp normalize_tree_label(value), do: to_string(value)

  defp tree_node_children(node) do
    node
    |> tree_node_lookup(:children, [])
    |> normalize_tree_children()
  end

  defp tree_node_expandable(node, default) do
    node
    |> tree_node_lookup(:expandable?, default)
    |> normalize_tree_expandable()
  end

  defp tree_row_prefix(_value, false, _visible_expanded, _assigns), do: " "

  defp tree_row_prefix(value, true, %MapSet{} = visible_expanded, assigns) do
    if MapSet.member?(visible_expanded, value),
      do: assigns.expanded_prefix,
      else: assigns.collapsed_prefix
  end

  defp tree_row_prefix(_value, _expandable?, _visible_expanded, _assigns), do: nil

  defp normalize_tree_children(children) when is_list(children), do: children
  defp normalize_tree_children(_children), do: []

  defp normalize_tree_expandable(value), do: value in [true, "true", "1", ""]

  defp controlled_tree_expanded(assigns) do
    if not is_nil(assigns.expanded) do
      tree_value_set(assigns.expanded)
    else
      nil
    end
  end

  defp rendered_tree_expanded(assigns) do
    cond do
      not is_nil(controlled_tree_expanded(assigns)) ->
        controlled_tree_expanded(assigns)

      tree_virtual?(assigns) ->
        case get_in(tree_implicit_state(assigns), [:expanded]) do
          %MapSet{} = expanded -> expanded
          expanded when not is_nil(expanded) -> tree_value_set(expanded)
          _ -> tree_value_set(assigns.default_expanded)
        end

      true ->
        nil
    end
  end

  defp tree_virtual?(assigns) do
    assigns.virtual in [true, "true", "1", ""] or
      not is_nil(normalize_tree_window_size(assigns.virtual_window))
  end

  defp tree_implicit_state(assigns) do
    id = assigns.id

    with id when not is_nil(id) <- id,
         {Breeze.Implicit.Tree, state} <-
           get_in(assigns, [:__breeze_caller_assigns__, :breeze, :implicit_state, id]) do
      state
    else
      _ -> nil
    end
  end

  defp render_tree_children?(nil, _value), do: true
  defp render_tree_children?(%MapSet{} = expanded, value), do: MapSet.member?(expanded, value)

  defp tree_value_set(%MapSet{} = values), do: values
  defp tree_value_set(values) when is_list(values), do: MapSet.new(values)

  defp tree_value_set(values) when is_map(values) do
    values
    |> Enum.filter(fn {_key, value} -> value in [true, "true", "1", ""] end)
    |> Enum.map(fn {key, _value} -> key end)
    |> MapSet.new()
  end

  defp tree_value_set(value), do: MapSet.new([value])

  defp tree_node_lookup(node, key, default) when is_map(node) do
    cond do
      Map.has_key?(node, key) -> Map.get(node, key)
      Map.has_key?(node, to_string(key)) -> Map.get(node, to_string(key))
      true -> Map.get(node, key_to_existing_atom(key), default)
    end
  end

  defp tree_node_lookup(node, key, default) when is_list(node) do
    if Keyword.keyword?(node) do
      cond do
        Keyword.has_key?(node, key) -> Keyword.get(node, key)
        Keyword.has_key?(node, to_string(key)) -> Keyword.get(node, to_string(key))
        true -> Keyword.get(node, key_to_existing_atom(key), default)
      end
    else
      default
    end
  end

  defp tree_node_lookup(_node, _key, default), do: default

  defp tree_prefix_width(prefix) when is_binary(prefix), do: max(Ucwidth.width(prefix), 0)
  defp tree_prefix_width(_prefix), do: 0

  defp size_class(axis, :full), do: "#{axis}-full"
  defp size_class(axis, size) when is_integer(size), do: "#{axis}-#{size}"

  attr :id, :string, required: true
  attr :selected, :string, default: nil
  attr :variant, :string, default: "default"
  attr :highlight, :string, default: "primary"
  attr :panel, :boolean, default: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :item_class, :string, default: nil
  attr :item_style, :any, default: nil
  attr :rest, :global

  slot :tab do
    attr :value, :string, required: true
    attr :label, :string, required: true
    attr :highlight, :string, default: nil
  end

  def tabs(%{variant: "underline"} = assigns) do
    active =
      Enum.find(assigns.tab, List.first(assigns.tab), &(&1.value == assigns[:selected]))

    highlight = Map.get(assigns, :highlight, "primary")
    highlight_text_class = semantic_class("text", highlight)
    highlight_bg_class = semantic_class("bg", highlight)

    assigns =
      assigns
      |> assign(panel: Map.get(assigns, :panel, true))
      |> assign(active: active)
      |> assign(highlight: highlight)
      |> assign(highlight_text_class: highlight_text_class)
      |> assign(highlight_bg_class: highlight_bg_class)
      |> assign(
        class:
          merge_class(
            "bg-panel overflow-hidden",
            class_override(assigns)
          )
      )
      |> assign(
        item_class:
          merge_class(
            "selected:bold selected:#{highlight_text_class} focus:selected:#{highlight_bg_class} focus:selected:text-bg overflow-hidden",
            class_override(assigns, :item_class, :item_style)
          )
      )

    render_underline_tabs(assigns)
  end

  def tabs(assigns) do
    active =
      Enum.find(assigns.tab, List.first(assigns.tab), &(&1.value == assigns[:selected]))

    highlight = Map.get(assigns, :highlight, "primary")
    highlight_text_class = semantic_class("text", highlight)
    highlight_bg_class = semantic_class("bg", highlight)
    highlight_border_class = semantic_class("border", highlight)

    assigns =
      assigns
      |> assign(panel: Map.get(assigns, :panel, true))
      |> assign(active: active)
      |> assign(highlight: highlight)
      |> assign(highlight_text_class: highlight_text_class)
      |> assign(highlight_bg_class: highlight_bg_class)
      |> assign(highlight_border_class: highlight_border_class)
      |> assign(
        class:
          merge_class(
            "border overflow-hidden focus:#{highlight_border_class}",
            class_override(assigns)
          )
      )
      |> assign(
        item_class:
          merge_class(
            "selected:bold selected:#{highlight_text_class} focus:selected:#{highlight_bg_class} focus:selected:text-bg overflow-scroll",
            class_override(assigns, :item_class, :item_style)
          )
      )

    render_default_tabs(assigns)
  end

  defp render_default_tabs(assigns) do
    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.Tabs}
      focusable
      tab-delegate={if @panel && @active do
      "#{@id}-panel-#{@active.value}"
    end}
      tab-selected={@active.value}
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      <box
        class={if @panel do
      "inline width-full height-1 overflow-hidden"
    else
      "inline height-1 overflow-hidden"
    end}
        tab-bar="true"
      >
        <box
          :for={t <- @tab}
          id={"#{@id}-tab-#{t.value}"}
          value={t.value}
          focus-with-owner="true"
          tab-label={t.label}
          class={Breeze.Blocks.tab_item_class(@item_class, t, @highlight)}
          style={Breeze.Blocks.inline_style(assigns, :item_class, :item_style)}
        >
          {" #{t.label} "}
        </box>
      </box>
      <box :if={@panel} class="height-full overflow-hidden">{render_slot(@active)}</box>
    </box>
    """
  end

  defp render_underline_tabs(assigns) do
    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.Tabs}
      focusable
      tab-delegate={if @panel && @active do
      "#{@id}-panel-#{@active.value}"
    end}
      tab-selected={@active.value}
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      <box
        class={if @panel do
      "inline width-full height-1 overflow-hidden"
    else
      "inline height-1 overflow-hidden"
    end}
        tab-bar="true"
      >
        <box
          :for={t <- @tab}
          id={"#{@id}-tab-#{t.value}"}
          value={t.value}
          focus-with-owner="true"
          tab-label={t.label}
          class={Breeze.Blocks.tab_item_class(@item_class, t, @highlight) <> " width-#{String.length(t.label) + 2}"}
          style={%{height: 1, overflow: :hidden}}
        >
          {" #{t.label} "}
        </box>
      </box>
      <box
        class={if @panel do
      "inline width-full height-1 overflow-hidden"
    else
      "inline height-1 overflow-hidden"
    end}
        tab-bar="true"
      >
        <box
          :for={t <- @tab}
          value={t.value}
          class={Breeze.Blocks.tab_indicator_class(t, @highlight) <>
      " width-#{String.length(t.label) + 2} height-1 overflow-hidden content-repeat-x"}
        >
          ━
        </box>
        <box :if={@panel} class="width-full text-mute-40 overflow-hidden content-repeat-x">━</box>
      </box>
      <box :if={@panel} class="height-full overflow-hidden">{render_slot(@active)}</box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, default: []
  attr :selected, :any, default: nil
  attr :row_value, :any, default: :id
  attr :loop, :boolean, default: true
  attr :scroll_padding, :integer, default: 0
  attr :empty, :string, default: "No rows"
  attr :rest, :global

  slot :col do
    attr :label, :string, default: nil
    attr :width, :integer, default: nil
    attr :align, :any, default: "left"
    attr :class, :string, default: nil
    attr :style, :any, default: nil
  end

  def table(assigns) do
    rows = Map.get(assigns, :rows, [])
    columns = normalize_table_columns(assigns.col, rows)
    rows = normalize_table_rows(rows, columns, Map.get(assigns, :row_value, :id))

    assigns =
      assigns
      |> assign(columns: columns)
      |> assign(rows: rows)
      |> assign(cell_class: "height-1 overflow-hidden selected:bg-primary selected:text-bg")

    ~H"""
    <box
      class="border width-full height-8 overflow-hidden bg-panel focus:border-primary"
      focus-within="true"
    >
      <box
        :if={@columns != []}
        class="inline width-full height-1 overflow-hidden bold bg-emphasize-20"
      >
        <box :for={column <- @columns} class={column.header_class}>{column.label}</box>
      </box>
      <box
        id={@id}
        focusable
        implicit={Breeze.Implicit.List}
        list-loop={@loop}
        list-selected={@selected}
        list-scroll-padding={@scroll_padding}
        class="height-full width-full overflow-scroll scrollbar-arrows focus:scrollbar-primary"
        {@rest}
      >
        <box :if={@rows == []} class="width-full height-1 text-muted">{@empty}</box>
        <box
          :for={row <- @rows}
          value={row.value}
          focus-with-owner
          class="inline width-full height-1 overflow-hidden selected:bg-primary selected:text-bg"
        >
          <box
            :for={cell <- row.cells}
            selected-with-owner
            class={Breeze.Blocks.merge_class(@cell_class, cell.class)}
            style={cell.style}
          >
            {render_slot(cell.slot, cell.row)}
          </box>
        </box>
      </box>
    </box>
    """
  end

  defp normalize_table_columns(columns, rows) do
    columns =
      Enum.map(columns, fn column ->
        %{
          slot: column,
          label: Map.get(column, :label) || "",
          width: Map.get(column, :width),
          align: normalize_align(Map.get(column, :align, "left")),
          class: Map.get(column, :class),
          style: Map.get(column, :style)
        }
      end)

    Enum.map(columns, fn column ->
      width = column.width || inferred_table_column_width(column, rows)
      align_class = table_align_class(column.align)

      column
      |> Map.put(:width, width)
      |> Map.put(
        :header_class,
        "width-#{width} padding-left-1 padding-right-1 overflow-hidden #{align_class}"
      )
      |> Map.put(
        :cell_class,
        "width-#{width} padding-left-1 padding-right-1 overflow-hidden #{align_class}"
      )
    end)
  end

  defp inferred_table_column_width(column, rows) do
    rows
    |> Enum.map(fn row -> render_slot(column.slot, row) |> Ucwidth.width() end)
    |> Kernel.++([Ucwidth.width(column.label), 4])
    |> Enum.max()
  end

  defp normalize_table_rows(rows, columns, row_value) do
    Enum.map(rows, fn row ->
      %{
        value: table_row_value(row, row_value),
        cells:
          Enum.map(columns, fn column ->
            %{
              slot: column.slot,
              row: row,
              class: merge_class(column.cell_class, column.class),
              style: column.style
            }
          end)
      }
    end)
  end

  defp table_row_value(row, fun) when is_function(fun, 1), do: fun.(row)

  defp table_row_value(row, nil), do: row

  defp table_row_value(row, key) when is_atom(key) or is_binary(key) do
    table_row_lookup(row, key, row)
  end

  defp table_row_value(row, _row_value), do: row

  defp table_row_lookup(row, key, default) when is_map(row) do
    Map.get(row, key) || Map.get(row, to_string(key)) || Map.get(row, key_to_existing_atom(key)) ||
      default
  end

  defp table_row_lookup(_row, _key, default), do: default

  defp key_to_existing_atom(key) when is_atom(key), do: key

  defp key_to_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp key_to_existing_atom(_key), do: nil

  defp normalize_align(value) when value in [:right, "right"], do: :right
  defp normalize_align(value) when value in [:center, "center"], do: :center
  defp normalize_align(_value), do: :left

  defp table_align_class(:right), do: "text-right"
  defp table_align_class(:center), do: "text-center"
  defp table_align_class(_align), do: "text-left"

  attr :id, :string, default: nil
  attr :focusable, :boolean, default: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def button(assigns) do
    assigns =
      assigns
      |> assign(focusable: normalize_button_focusable(Map.get(assigns, :focusable, true)))
      |> assign(
        class:
          merge_class(
            "bg-primary text-bg bold height-1 overflow-hidden focus:inverse padding-left-1 padding-right-1",
            class_override(assigns)
          )
      )

    ~H"""
    <box
      id={@id}
      focusable={@focusable}
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </box>
    """
  end

  defp normalize_button_focusable(value) when value in [false, "false"], do: false
  defp normalize_button_focusable(_value), do: true

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :"input-value", :string, default: ""
  attr :"input-cursor", :any, default: nil
  attr :"input-placeholder", :string, default: nil
  attr :rest, :global

  slot :inner_block

  def input(assigns) do
    assigns =
      assign(assigns,
        class:
          merge_class(
            "input height-1 overflow-hidden padding-left-1 text mute-text-22 bg-emphasize-24 focus:text focus:mute-text-0 focus:emphasize-bg-34 placeholder:mute-text-16",
            class_override(assigns)
          )
      )

    ~H"""
    <box
      id={@id}
      focusable
      implicit={Breeze.Implicit.Input}
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      input-value={assigns[:"input-value"]}
      input-cursor={assigns[:"input-cursor"]}
      input-placeholder={assigns[:"input-placeholder"]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </box>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :"textarea-value", :string, default: ""
  attr :"textarea-cursor", :any, default: nil
  attr :"textarea-placeholder", :string, default: nil
  attr :"textarea-prefix", :string, default: nil
  attr :"textarea-submit-on-enter", :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :rest, :global

  def textarea(assigns) do
    prefix = normalize_textarea_prefix(assigns[:"textarea-prefix"])
    disabled? = normalize_textarea_disabled(assigns[:disabled])
    layout_prefix = if disabled?, do: nil, else: prefix

    assigns =
      assigns
      |> assign(disabled: disabled?)
      |> assign(focusable: !disabled?)
      |> assign(implicit: if(disabled?, do: nil, else: Breeze.Implicit.Textarea))
      |> assign(
        textarea_value: textarea_display_value(assigns[:"textarea-value"], prefix, disabled?)
      )
      |> assign(textarea_prefix: layout_prefix)
      |> assign(class: textarea_class(assigns, layout_prefix))
      |> assign(prefix_class: textarea_prefix_class(assigns, layout_prefix))

    ~H"""
    <box class={if @textarea_prefix do
      "relative"
    else
      nil
    end}>
      <box :if={@textarea_prefix} class={@prefix_class}>{@textarea_prefix}</box>
      <box
        id={@id}
        focusable={@focusable}
        implicit={@implicit}
        class={@class}
        style={Breeze.Blocks.inline_style(assigns)}
        textarea-value={assigns[:"textarea-value"]}
        textarea-cursor={assigns[:"textarea-cursor"]}
        textarea-placeholder={assigns[:"textarea-placeholder"]}
        textarea-submit-on-enter={assigns[:"textarea-submit-on-enter"]}
        {@rest}
      >
        {@textarea_value}
      </box>
    </box>
    """
  end

  defp normalize_textarea_disabled(value), do: value in [true, "true", ""]

  defp textarea_display_value(value, nil, _disabled?), do: value
  defp textarea_display_value(value, _prefix, false), do: value

  defp textarea_display_value(value, prefix, true) do
    continuation = String.duplicate(" ", String.length(prefix))

    value
    |> String.split("\n", trim: false)
    |> Enum.with_index()
    |> Enum.map(fn
      {line, 0} -> prefix <> line
      {line, _index} -> continuation <> line
    end)
    |> Enum.join("\n")
  end

  attr :id, :string, required: true
  attr :content, :string, required: true
  attr :width, :integer, required: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil

  def markdown(assigns) do
    assigns =
      assign(assigns,
        class:
          merge_class(
            "height-full overflow-scroll scrollbar-arrows",
            class_override(assigns)
          )
      )

    ~H"""
    <.scroll id={@id} class={@class} style={Breeze.Blocks.inline_style(assigns)}>
      {Breeze.Markdown.render(@content, @width)}
    </.scroll>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def scroll(assigns) do
    assigns =
      assign(assigns,
        class:
          merge_class(
            "height-full overflow-scroll scrollbar-arrows",
            class_override(assigns)
          )
      )

    ~H"""
    <box
      focusable
      id={@id}
      implicit={Breeze.Implicit.Scroll}
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </box>
    """
  end

  attr :id, :string, default: nil
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :scroll, :boolean, default: false
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :title_class, :string, default: nil
  attr :title_style, :any, default: nil
  attr :scroll_class, :string, default: nil
  attr :scroll_style, :any, default: nil
  attr :focus_within, :boolean, default: true
  attr :rest, :global

  slot :title
  slot :inner_block

  def panel(assigns) do
    panel_class =
      merge_class(
        "border-rounded border-stroke bg-panel focus:border-primary",
        class_override(assigns)
      )

    assigns =
      assigns
      |> assign(
        focus_within: Map.get(assigns, :focus_within, true),
        class: panel_class,
        title_class:
          merge_class(
            "bold #{panel_title_class(panel_class)}",
            class_override(assigns, :title_class, :title_style)
          )
      )
      |> assign(
        scroll_class:
          merge_class(
            "width-full height-full bg-panel scrollbar-arrows",
            class_override(assigns, :scroll_class, :scroll_style)
          )
      )

    assigns =
      assign(
        assigns,
        frame_class:
          panel_frame_class(assigns.class, Map.get(assigns, :width), Map.get(assigns, :height))
      )

    if assigns[:scroll] do
      if is_nil(assigns[:id]) do
        raise ArgumentError, "panel requires an id when scroll: true"
      end

      ~H"""
      <box
        class={@frame_class}
        style={Breeze.Blocks.inline_style(assigns)}
        focus-within={@focus_within}
        {@rest}
      >
        <box
          :if={assigns[:title]}
          focus-within="true"
          class={"absolute left-2 top-0 #{@title_class}"}
          style={Breeze.Blocks.inline_style(assigns, :title_class, :title_style)}
        >
          {render_slot(@title)}
        </box>
        <.scroll
          id={@id}
          class={@scroll_class}
          style={Breeze.Blocks.inline_style(assigns, :scroll_class, :scroll_style)}
        >
          {render_slot(@inner_block)}
        </.scroll>
      </box>
      """
    else
      ~H"""
      <box
        id={@id}
        class={@frame_class}
        style={Breeze.Blocks.inline_style(assigns)}
        focus-within={@focus_within}
        {@rest}
      >
        {render_slot(@inner_block)}
        <box
          :if={assigns[:title]}
          focus-within="true"
          class={"absolute left-2 top-0 #{@title_class}"}
          style={Breeze.Blocks.inline_style(assigns, :title_class, :title_style)}
        >
          {render_slot(@title)}
        </box>
      </box>
      """
    end
  end

  defp panel_frame_class(class, width, height) do
    class
    |> maybe_append_dimension(:width, width)
    |> maybe_append_dimension(:height, height)
  end

  defp panel_title_class(class) do
    class
    |> to_string()
    |> String.split()
    |> Enum.reduce([], fn token, acc ->
      case token do
        "border-" <> rest when rest not in ["rounded"] -> ["text-" <> rest | acc]
        "focus:border-" <> rest -> ["focus:text-" <> rest | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp maybe_append_dimension(class, _dimension, nil), do: class
  defp maybe_append_dimension(class, :width, width), do: "#{class} width-#{width}"
  defp maybe_append_dimension(class, :height, height), do: "#{class} height-#{height}"

  attr :id, :string, required: true
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :inset, :integer, default: nil
  attr :inset_x, :integer, default: nil
  attr :inset_y, :integer, default: nil
  attr :dim, :boolean, default: false
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :frame_class, :string, default: nil
  attr :frame_style, :any, default: nil
  attr :rest, :global

  slot :title
  slot :inner_block

  def modal(assigns) do
    {frame_class, panel_class} =
      case {assigns[:width], assigns[:height], assigns[:inset], assigns[:inset_x],
            assigns[:inset_y]} do
        {width, height, nil, nil, nil} when is_integer(width) and is_integer(height) ->
          {
            merge_class(
              "fixed center width-#{width} height-#{height} bg layer-50",
              class_override(assigns, :frame_class, :frame_style)
            ),
            merge_class(
              "absolute left-0 top-0 right-0 bottom-0 layer-51 width-full height-full border-rounded border-stroke bg",
              class_override(assigns)
            )
          }

        {nil, nil, inset, nil, nil} when is_integer(inset) ->
          {
            merge_class(
              "fixed inset-#{inset} width-screen height-screen bg layer-50",
              class_override(assigns, :frame_class, :frame_style)
            ),
            merge_class(
              "absolute left-0 right-0 top-0 bottom-0 layer-51 width-full height-full border-rounded border-stroke bg",
              class_override(assigns)
            )
          }

        {nil, nil, nil, inset_x, inset_y}
        when is_integer(inset_x) and is_integer(inset_y) ->
          {
            merge_class(
              "fixed inset-x-#{inset_x} inset-y-#{inset_y} width-screen height-screen bg layer-50",
              class_override(assigns, :frame_class, :frame_style)
            ),
            merge_class(
              "absolute left-0 right-0 top-0 bottom-0 layer-51 width-full height-full border-rounded border-stroke bg",
              class_override(assigns)
            )
          }

        _ ->
          raise ArgumentError,
                "modal requires either width/height, inset, or inset_x/inset_y"
      end

    assigns =
      assigns
      |> assign(frame_class: frame_class)
      |> assign(panel_class: panel_class)

    ~H"""
    <box
      id={@id}
      focusable
      focus-scope="trap"
      implicit={Breeze.Implicit.Modal}
      screen-dim={@dim}
      class={@frame_class}
      style={Breeze.Blocks.inline_style(assigns, :frame_class, :frame_style)}
      {@rest}
    >
      <box class={@panel_class} style={Breeze.Blocks.inline_style(assigns)}>
        <box :if={assigns[:title]} class="absolute left-2 top-0 bold text">{render_slot(@title)}</box>
        {render_slot(@inner_block)}
      </box>
    </box>
    """
  end

  @doc """
  Merge two class strings, with `override` taking precedence over `default` for
  matching style properties.

  The *property key* for each style token is everything before its final `-`
  segment, so tokens that share the same prefix override one another:

      iex> Breeze.Blocks.merge_class("border width-24 height-8", "width-32")
      "border width-32 height-8"

      iex> Breeze.Blocks.merge_class("overflow-scroll", "overflow-hidden")
      "overflow-hidden"

  Tokens from `override` that do not match any default key are appended:

      iex> Breeze.Blocks.merge_class("border width-24", "bg-4")
      "border width-24 bg-4"

  `nil` or an empty string override returns the default unchanged.
  """
  @spec merge_class(String.t(), String.t() | nil) :: String.t()
  def merge_class(default, override) when override in [nil, ""], do: default

  def merge_class(default, override) do
    default_tokens = String.split(default, " ", trim: true)
    override_tokens = String.split(override, " ", trim: true)

    default_key_set = MapSet.new(default_tokens, &style_key/1)
    override_map = Map.new(override_tokens, fn token -> {style_key(token), token} end)

    merged =
      Enum.map(default_tokens, fn token -> Map.get(override_map, style_key(token), token) end)

    new_tokens = Enum.reject(override_tokens, &MapSet.member?(default_key_set, style_key(&1)))

    Enum.join(merged ++ new_tokens, " ")
  end

  @spec merge_style(String.t(), String.t() | nil) :: String.t()
  def merge_style(default, override), do: merge_class(default, override)

  defp class_override(assigns, class_key \\ :class, style_key \\ :style) do
    cond do
      is_binary(assigns[class_key]) -> assigns[class_key]
      is_binary(assigns[style_key]) -> assigns[style_key]
      true -> nil
    end
  end

  @doc false
  def inline_style(assigns, class_key \\ :class, style_key \\ :style) do
    cond do
      not is_nil(assigns[class_key]) and not is_binary(assigns[class_key]) -> assigns[class_key]
      not is_binary(assigns[style_key]) -> assigns[style_key]
      true -> nil
    end
  end

  defp style_key(token) do
    case String.split(token, "-") do
      [_only] -> token
      parts -> parts |> Enum.drop(-1) |> Enum.join("-")
    end
  end

  @doc false
  def tab_item_class(base_class, tab, default_highlight) do
    highlight = Map.get(tab, :highlight) || default_highlight
    highlight_text_class = semantic_class("text", highlight)
    highlight_bg_class = semantic_class("bg", highlight)

    "#{base_class} selected:#{highlight_text_class} focus:selected:#{highlight_bg_class}"
  end

  @doc false
  def tab_indicator_class(tab, default_highlight) do
    highlight = Map.get(tab, :highlight) || default_highlight
    highlight_class = semantic_class("text", highlight)

    "text-mute-40 selected:text-mute-0 selected:#{highlight_class} focus:selected:#{highlight_class}"
  end

  defp semantic_class(prefix, nil), do: prefix
  defp semantic_class(prefix, name), do: "#{prefix}-#{name}"

  defp textarea_class(assigns, nil) do
    merge_class(
      "input border-rounded border-stroke bg-panel text mute-text-22 focus:text focus:mute-text-0 focus:border-primary placeholder:mute-text-16 padding-left-1 padding-right-1 height-5 overflow-hidden",
      class_override(assigns)
    )
  end

  defp textarea_class(assigns, prefix) do
    base_class =
      merge_class(
        "input border-rounded border-stroke bg-panel text mute-text-22 focus:text focus:mute-text-0 focus:border-primary placeholder:mute-text-16 padding-left-1 padding-right-1 height-5 overflow-hidden",
        class_override(assigns)
      )

    prefix_width =
      textarea_prefix_width(prefix)

    padding_left = textarea_padding_left(base_class, inline_style(assigns))

    merge_class(base_class, "padding-left-#{padding_left + prefix_width}")
  end

  defp textarea_prefix_class(_assigns, nil), do: nil

  defp textarea_prefix_class(assigns, prefix) do
    base_class =
      merge_class(
        "input border-rounded border-stroke bg-panel text mute-text-22 focus:text focus:mute-text-0 focus:border-primary placeholder:mute-text-16 padding-left-1 padding-right-1 height-5 overflow-hidden",
        class_override(assigns)
      )

    {left, top} = textarea_prefix_offsets(base_class, inline_style(assigns))
    width = max(textarea_prefix_width(prefix), 1)

    [
      textarea_prefix_visual_class(base_class, placeholder_visible?(assigns)),
      "absolute left-#{left} top-#{top} width-#{width} height-1 overflow-hidden"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp textarea_prefix_offsets(class, style) do
    border_inset = if(textarea_has_border?(class, style), do: 1, else: 0)

    {
      border_inset + textarea_padding_value(:left, class, style),
      border_inset + textarea_padding_value(:top, class, style)
    }
  end

  defp textarea_padding_left(class, style) do
    textarea_padding_value(:left, class, style)
  end

  defp textarea_padding_value(side, class, style) do
    style_padding =
      case inline_padding_value(style, side) do
        value when is_integer(value) -> value
        _ -> nil
      end

    style_padding ||
      token_padding_value(style_tokens(class, style), side) ||
      0
  end

  defp textarea_has_border?(class, style) do
    case inline_border_value(style) do
      nil ->
        style_tokens(class, style)
        |> Enum.reduce(false, fn token, border? ->
          case token do
            "border-none" -> false
            "border" -> true
            "border-rounded" -> true
            "border-invisible" -> true
            _ -> border?
          end
        end)

      false ->
        false

      _other ->
        true
    end
  end

  defp style_tokens(class, style) do
    [class, if(is_binary(style), do: style, else: nil)]
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&String.split(&1, " ", trim: true))
  end

  defp token_padding_value(tokens, side) do
    Enum.reduce(tokens, nil, fn token, padding ->
      case side do
        :left ->
          parse_padding_token(token, ~r/^padding-left-(\d+)$/, ~r/^padding-(\d+)$/) || padding

        :top ->
          parse_padding_token(token, ~r/^padding-top-(\d+)$/, ~r/^padding-(\d+)$/) || padding
      end
    end)
  end

  defp parse_padding_token(token, specific_pattern, generic_pattern) do
    case Regex.run(specific_pattern, token, capture: :all_but_first) ||
           Regex.run(generic_pattern, token, capture: :all_but_first) do
      [value] -> String.to_integer(value)
      _ -> nil
    end
  end

  defp inline_padding_value(style, side) when is_list(style) do
    if Keyword.keyword?(style), do: inline_padding_value(Map.new(style), side), else: nil
  end

  defp inline_padding_value(%BackBreeze.Style{} = style, side),
    do: inline_padding_value(Map.from_struct(style), side)

  defp inline_padding_value(%_{} = style, side),
    do: inline_padding_value(Map.from_struct(style), side)

  defp inline_padding_value(style, side) when is_map(style) do
    case side do
      :left -> Map.get(style, :padding_left) || Map.get(style, :padding)
      :top -> Map.get(style, :padding_top) || Map.get(style, :padding)
    end
  end

  defp inline_padding_value(_style, _side), do: nil

  defp inline_border_value(style) when is_list(style) do
    if Keyword.keyword?(style), do: inline_border_value(Map.new(style)), else: nil
  end

  defp inline_border_value(%BackBreeze.Style{} = style),
    do: inline_border_value(Map.from_struct(style))

  defp inline_border_value(%_{} = style),
    do: inline_border_value(Map.from_struct(style))

  defp inline_border_value(style) when is_map(style), do: Map.get(style, :border)
  defp inline_border_value(_style), do: nil

  defp normalize_textarea_prefix(prefix) when is_binary(prefix) and prefix != "", do: prefix
  defp normalize_textarea_prefix(_prefix), do: nil

  defp placeholder_visible?(assigns) do
    assigns[:"textarea-value"] in [nil, ""] and is_binary(assigns[:"textarea-placeholder"]) and
      assigns[:"textarea-placeholder"] != ""
  end

  defp textarea_prefix_visual_class(base_class, placeholder?) do
    tokens = String.split(base_class, " ", trim: true)

    [
      last_token_for_key(tokens, "bg"),
      if(placeholder?,
        do:
          last_token_for_key(tokens, "placeholder:mute-text")
          |> maybe_strip_placeholder_prefix(),
        else: last_token_for_key(tokens, "text")
      ),
      if(placeholder?, do: nil, else: last_token_for_key(tokens, "mute-text")),
      if(placeholder?, do: nil, else: last_token_for_key(tokens, "focus:text")),
      if(placeholder?, do: nil, else: last_token_for_key(tokens, "focus:mute-text"))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp last_token_for_key(tokens, key) do
    tokens
    |> Enum.reverse()
    |> Enum.find(&(style_key(&1) == key))
  end

  defp maybe_strip_placeholder_prefix("placeholder:" <> token), do: token
  defp maybe_strip_placeholder_prefix(token), do: token

  defp textarea_prefix_width(prefix) when is_binary(prefix) do
    prefix
    |> String.graphemes()
    |> Enum.reduce(0, fn grapheme, total -> total + max(Ucwidth.width(grapheme), 0) end)
  end
end
