defmodule Breeze.Renderer do
  @moduledoc false

  alias BackBreeze.Box
  alias BackBreeze.VirtualText
  alias Breeze.Style, as: RenderStyle
  alias Breeze.Theme

  def render_to_string(mod, assigns, opts \\ []) do
    {_, %{content: content}} = render(mod, assigns, opts)
    content
  end

  def render_tree(mod, assigns, opts \\ []) do
    assigns = put_breeze_render_context(assigns, opts)

    opts =
      Keyword.put_new(
        opts,
        :apply_theme_defaults,
        Breeze.Theme.defaults_enabled?(
          Keyword.get(opts, :theme_source, Keyword.get(opts, :theme))
        )
      )

    rendered = mod.render(assigns)

    [{root_tag, _, root_children}] =
      rendered
      |> Breeze.Template.render_to_tree(assigns)

    opts = maybe_attach_live_viewports(root_tag, root_children, opts)
    build_from_tree_nodes(root_tag, root_children, opts)
  end

  def render(mod, assigns, opts \\ []) do
    assigns = put_breeze_render_context(assigns, opts)

    opts =
      Keyword.put_new(
        opts,
        :apply_theme_defaults,
        Breeze.Theme.defaults_enabled?(
          Keyword.get(opts, :theme_source, Keyword.get(opts, :theme))
        )
      )

    profile_scope = Keyword.get(opts, :profile_scope)
    profile_label = Keyword.get(opts, :profile_label, inspect(mod))

    rendered =
      profile(profile_scope, profile_label, :view_render_us, fn ->
        mod.render(assigns)
      end)

    [{root_tag, _, root_children}] =
      profile(profile_scope, profile_label, :template_tree_us, fn ->
        Breeze.Template.render_to_tree(rendered, assigns)
      end)

    opts = maybe_attach_live_viewports(root_tag, root_children, opts)

    {acc, box} =
      profile(profile_scope, profile_label, :build_tree_us, fn ->
        build_from_tree_nodes(root_tag, root_children, opts)
      end)

    %{box: box, dimensions: dimensions} =
      profile(profile_scope, profile_label, :layout_us, fn ->
        BackBreeze.Box.render_with_dimensions(box, opts)
      end)

    acc = maybe_refresh_live_dimensions(root_tag, root_children, opts, acc)
    box = maybe_dim_screen_backdrop(box, acc, dimensions, root_children, opts)

    emit_metric(profile_scope, profile_label, :element_count, map_size(acc.elements))

    {Map.put(acc, :dimensions, dimensions), box}
  end

  defp put_breeze_render_context(assigns, opts) when is_map(assigns) do
    context = render_context(opts)

    Map.update(assigns, :breeze, Map.put(context, :flash, []), fn
      breeze when is_map(breeze) -> breeze |> Map.merge(context) |> Map.put_new(:flash, [])
      _ -> Map.put(context, :flash, [])
    end)
  end

  defp put_breeze_render_context(assigns, _opts), do: assigns

  defp render_context(opts) do
    %{
      terminal: terminal_context(Keyword.get(opts, :terminal)),
      implicit_state: Keyword.get(opts, :implicit_state, %{}),
      implicit_meta: Keyword.get(opts, :implicit_meta, %{})
    }
  end

  defp terminal_context(%{size: %{width: width, height: height}}) do
    %{width: width, height: height}
  end

  defp terminal_context(_terminal), do: nil

  defp build_from_tree_nodes(root_tag, children, opts) do
    {acc, box} =
      build_tree(
        children,
        %BackBreeze.Box{},
        [],
        RenderStyle.empty(),
        [],
        %{
          focusables: [],
          id: 0,
          elements: %{},
          boxes: %{},
          ids: [],
          flags: [],
          live_dimensions: %{},
          render_tree?: render_tree_enabled?(opts),
          render_tree_nodes: %{},
          render_tree_children: %{},
          render_tree_root: 0
        },
        opts,
        0,
        root_tag
      )

    acc = %{acc | elements: Map.put(acc.elements, acc.id, acc.flags)}
    ids = Enum.reverse(acc.ids)
    focusables = Enum.reverse(acc.focusables) |> then(&Enum.filter(ids, fn id -> id in &1 end))
    acc = %{acc | ids: ids, focusables: focusables}

    acc =
      if acc.render_tree? do
        acc
        |> Map.put(:render_tree, assemble_render_tree(acc))
        |> Map.drop([:render_tree?, :render_tree_nodes, :render_tree_children, :render_tree_root])
      else
        Map.drop(acc, [
          :render_tree?,
          :render_tree_nodes,
          :render_tree_children,
          :render_tree_root
        ])
      end

    {acc, box}
  end

  defp render_tree_enabled?(opts), do: Keyword.get(opts, :render_tree?, false) == true

  defp put_render_tree_node(%{render_tree?: true} = acc, idx, tag) do
    update_in(acc, [:render_tree_nodes], &Map.put(&1 || %{}, idx, %{idx: idx, tag: tag}))
  end

  defp put_render_tree_node(acc, _idx, _tag), do: acc

  defp put_render_tree_child(%{render_tree?: true} = acc, parent_id, child_ref) do
    update_in(acc, [:render_tree_children], fn children ->
      Map.update(children || %{}, parent_id, [child_ref], &(&1 ++ [child_ref]))
    end)
  end

  defp put_render_tree_child(acc, _parent_id, _child_ref), do: acc

  defp assemble_render_tree(%{render_tree_root: root} = acc) do
    assemble_render_tree(root, acc.render_tree_nodes, acc.render_tree_children)
  end

  defp assemble_render_tree(idx, nodes, children) do
    case Map.get(nodes, idx) do
      nil ->
        nil

      node ->
        child_nodes =
          children
          |> Map.get(idx, [])
          |> Enum.flat_map(fn
            {:id, child_id} ->
              case assemble_render_tree(child_id, nodes, children) do
                nil -> []
                child -> [child]
              end

            {:tree, child} when is_map(child) ->
              [child]

            _other ->
              []
          end)

        Map.put(node, :children, child_nodes)
    end
  end

  defp shift_render_tree(nil, _offset), do: nil

  defp shift_render_tree(%{idx: idx} = node, offset) do
    children =
      node
      |> Map.get(:children, [])
      |> Enum.map(&shift_render_tree(&1, offset))
      |> Enum.reject(&is_nil/1)

    node
    |> Map.put(:idx, idx + offset)
    |> Map.put(:children, children)
  end

  defp build_tree(
         [{:attribute, ["style", style]} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    acc = %{acc | flags: Keyword.put(acc.flags, :style_input, style)}
    flags = Keyword.put(flags, :style_input, style)

    build_tree(
      rest,
      box,
      children,
      RenderStyle.put_style(style_state, style),
      flags,
      acc,
      opts,
      current_id,
      tag
    )
  end

  defp build_tree(
         [{:attribute, ["class", class]} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    acc = %{acc | flags: Keyword.put(acc.flags, :class, class)}
    flags = Keyword.put(flags, :class, class)

    build_tree(
      rest,
      box,
      children,
      RenderStyle.put_class(style_state, class),
      flags,
      acc,
      opts,
      current_id,
      tag
    )
  end

  defp build_tree(
         [{:attribute, ["id", box_id]} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    ids = [box_id | acc.ids]
    acc = %{acc | ids: ids, flags: Keyword.put(acc.flags, :id, box_id)}

    build_tree(
      rest,
      box,
      children,
      style_state,
      Keyword.put(flags, :id, box_id),
      acc,
      opts,
      current_id,
      tag
    )
  end

  defp build_tree(
         [{:attribute, ["implicit", mod]} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    mod =
      case mod do
        value when is_atom(value) -> value
        value -> String.to_atom(to_string(value))
      end

    acc = %{acc | flags: Keyword.put(acc.flags, :implicit, mod)}

    build_tree(
      rest,
      box,
      children,
      style_state,
      Keyword.put(flags, :implicit, mod),
      acc,
      opts,
      current_id,
      tag
    )
  end

  defp build_tree(
         [{:attribute, ["content", content]} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    acc = %{acc | flags: Keyword.put(acc.flags, :content, content)}

    build_tree(
      rest,
      %{box | content: content},
      children,
      style_state,
      Keyword.put(flags, :content, content),
      acc,
      opts,
      current_id,
      tag
    )
  end

  defp build_tree(
         [{:attribute, [flag, value]} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    flag = String.to_atom(flag)
    acc = %{acc | flags: Keyword.put(acc.flags, flag, value)}

    build_tree(
      rest,
      box,
      children,
      style_state,
      Keyword.put(flags, flag, value),
      acc,
      opts,
      current_id,
      tag
    )
  end

  defp build_tree(
         [{:attribute_bool, [attr]} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    attr = String.to_atom(attr)
    acc = %{acc | flags: Keyword.put(acc.flags, attr, true)}

    build_tree(
      rest,
      box,
      children,
      style_state,
      Keyword.put(flags, attr, true),
      acc,
      opts,
      current_id,
      tag
    )
  end

  defp build_tree([content | rest], box, children, style_state, flags, acc, opts, current_id, tag)
       when is_binary(content) do
    box = %{box | content: String.trim_trailing(content, "\n  ")}
    build_tree(rest, box, children, style_state, flags, acc, opts, current_id, tag)
  end

  defp build_tree([content | rest], box, children, style_state, flags, acc, opts, current_id, tag)
       when is_map(content) do
    if virtual_text_surface?(content) do
      box = %{box | content: content}
      build_tree(rest, box, children, style_state, flags, acc, opts, current_id, tag)
    else
      children = children ++ [content]
      build_tree(rest, box, children, style_state, flags, acc, opts, current_id, tag)
    end
  end

  defp build_tree([content | rest], box, children, style_state, flags, acc, opts, current_id, tag)
       when is_list(content) do
    if text_span_list?(content) do
      box = %{box | content: content}
      build_tree(rest, box, children, style_state, flags, acc, opts, current_id, tag)
    else
      children = children ++ [content]
      build_tree(rest, box, children, style_state, flags, acc, opts, current_id, tag)
    end
  end

  defp build_tree(
         [{:live, attrs} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       ) do
    {acc, child} =
      if Keyword.get(opts, :live_placeholder, false) do
        build_live_placeholder(attrs, flags, acc, opts, current_id)
      else
        case Keyword.get(opts, :live_view) do
          fun when is_function(fun, 2) ->
            id = fetch_live_attr!(attrs, :id)
            full_id = live_full_id(id, opts)
            viewport = get_in(opts, [:live_viewports, full_id])

            child_opts =
              opts
              |> Keyword.put(:live_viewport, viewport)
              |> Keyword.put(:live_focus_within_path, focus_within_path(flags))
              |> maybe_put_live_terminal(viewport)

            case fun.(attrs, child_opts) do
              {:rendered, prefix, child_acc, child_box} ->
                child_acc = namespace_live_acc(child_acc, prefix, child_opts)

                {merge_live_acc(acc, child_acc, current_id), child_box}

              {:rendered, prefix, child_acc, child_box, child_dimensions} ->
                child_acc = namespace_live_acc(child_acc, prefix, child_opts)

                {merge_live_acc(acc, child_acc, current_id), child_box}
                |> then(fn {merged_acc, rendered_box} ->
                  {
                    %{
                      merged_acc
                      | live_dimensions: Map.merge(merged_acc.live_dimensions, child_dimensions)
                    },
                    rendered_box
                  }
                end)

              :preloaded ->
                {acc, nil}

              _ ->
                {acc, nil}
            end

          _ ->
            {acc, nil}
        end
      end

    children = if child, do: [child | children], else: children
    build_tree(rest, box, children, style_state, flags, acc, opts, current_id, tag)
  end

  defp build_tree(
         [{child_tag, _, nodes} | rest],
         box,
         children,
         style_state,
         flags,
         acc,
         opts,
         current_id,
         tag
       )
       when is_atom(child_tag) do
    child_flags =
      []
      |> inherit_implicit_owner(flags)
      |> inherit_selected_owner_value(flags)
      |> inherit_focus_scope_path(flags)
      |> inherit_focus_within_path(flags)
      |> inherit_selected_with_owner(opts)

    child_id = acc.id + 1

    acc =
      %{
        acc
        | flags: child_flags,
          id: child_id,
          elements: Map.put(acc.elements, acc.id, acc.flags)
      }
      |> put_render_tree_child(current_id, {:id, child_id})

    {acc, child} =
      build_tree(
        nodes,
        %BackBreeze.Box{},
        [],
        RenderStyle.empty(),
        child_flags,
        acc,
        opts,
        child_id,
        child_tag
      )

    build_tree(rest, box, [child | children], style_state, flags, acc, opts, current_id, tag)
  end

  defp build_tree([], box, children, style_state, flags, acc, opts, current_id, tag) do
    render_opts = opts
    %{focusables: focusables} = acc
    implicit_state = Keyword.get(opts, :implicit_state, %{})
    implicit_owner = Keyword.get(flags, :implicit_owner)

    focused_target = Keyword.get(opts, :focused)
    owned_focus_target = implicit_owner
    node_focus_target = Keyword.get(flags, :id) || owned_focus_target
    root_id = Keyword.get(flags, :id)

    id =
      cond do
        Keyword.get(flags, :implicit) && root_id -> root_id
        implicit_owner -> implicit_owner
        true -> root_id
      end

    {implicit_mod, implicit} =
      case id && get_in(implicit_state, [id]) do
        nil -> {nil, nil}
        {mod, state} -> {mod, state}
      end

    focused =
      Keyword.get(flags, :focused, false) or
        (not is_nil(focused_target) &&
           Keyword.has_key?(flags, :"focus-with-owner") &&
           owned_focus_target == focused_target) or
        (not is_nil(focused_target) && node_focus_target == focused_target) or
        focused_within?(flags, root_id, focused_target, acc)

    selected_with_owner =
      implicit &&
        Keyword.has_key?(flags, :"selected-with-owner") &&
        not is_nil(Keyword.get(flags, :selected_owner_value)) &&
        Map.get(implicit, :selected) == Keyword.get(flags, :selected_owner_value)

    flags =
      flags
      |> then(fn flags -> if focused, do: Keyword.put(flags, :focused, true), else: flags end)
      |> then(fn flags ->
        if selected_with_owner, do: Keyword.put(flags, :selected, true), else: flags
      end)

    style_flags =
      []
      |> then(fn style_flags ->
        if focused, do: Keyword.put(style_flags, :focus, true), else: style_flags
      end)
      |> then(fn style_flags ->
        if Keyword.get(flags, :selected, false),
          do: Keyword.put(style_flags, :selected, true),
          else: style_flags
      end)

    type = if id == root_id, do: :root, else: :child

    previous_elements = Keyword.get(opts, :previous_elements, %{})
    previous_layout = if id, do: Map.get(previous_elements, id), else: nil

    {style_flags, style_modifiers, scroll_modifier} =
      if implicit do
        flags =
          if previous_layout,
            do: Keyword.put(flags, :layout_element, previous_layout),
            else: flags

        modifiers = implicit_mod.handle_modifiers(type, flags, implicit)
        parse_modifiers(modifiers, style_flags)
      else
        {style_flags, [], %{top: nil, left: nil}}
      end

    focusables =
      if Keyword.get(flags, :focusable),
        do: [Keyword.get(flags, :id) | focusables],
        else: focusables

    element =
      style_state
      |> RenderStyle.merge_modifiers(style_modifiers)
      |> RenderStyle.to_element(
        Keyword.merge(style_flags,
          theme: Keyword.get(opts, :theme),
          terminal: Keyword.get(opts, :terminal),
          apply_theme_defaults: Keyword.get(opts, :apply_theme_defaults, false)
        )
      )

    style =
      element.style
      |> maybe_resolve_intrinsic_inline_width(
        Enum.reverse(children),
        box.content,
        element.attributes
      )

    children =
      children
      |> Enum.reverse()
      |> maybe_resolve_inline_child_widths(style, element.attributes)

    opts =
      element.attributes
      |> merge_scroll_modifier(scroll_modifier)
      |> Map.put(:style, style)
      |> Map.put(:owner_id, id)

    content = box.content

    final_box = %{Box.new(opts) | children: children, content: content}

    final_box =
      if implicit && function_exported?(implicit_mod, :animate, 5) &&
           not Keyword.get(render_opts, :layout_prepass, false) do
        implicit_mod
        |> apply(:animate, [
          type,
          final_box,
          flags,
          implicit,
          animation_ctx(render_opts, id, focused, previous_layout)
        ])
        |> normalize_animation_result()
        |> elem(0)
      else
        final_box
      end

    stored_box = storage_box(final_box)

    boxes =
      acc.boxes
      |> Map.put(acc.id, stored_box)
      |> then(fn boxes ->
        if root_id, do: Map.put(boxes, root_id, stored_box), else: boxes
      end)

    acc =
      acc
      |> Map.put(:focusables, focusables)
      |> Map.put(:boxes, boxes)
      |> put_render_tree_node(current_id, tag)

    {acc, final_box}
  end

  defp storage_box(%Box{} = box) do
    if volatile_box?(box) do
      %{box | content: storage_content(box.content), children: [], layer_map: %{}}
    else
      box
    end
  end

  defp storage_content(%VirtualText{cache?: false}), do: ""
  defp storage_content(content), do: content

  defp volatile_box?(%Box{content: %VirtualText{cache?: false}}), do: true

  defp volatile_box?(%Box{children: children}) when is_list(children),
    do: Enum.any?(children, &volatile_box?/1)

  defp volatile_box?(_box), do: false

  defp parse_modifiers(modifiers, style_flags) when is_list(modifiers) do
    {style_flags, style_modifiers, scroll_modifier} =
      Enum.reduce(modifiers, {style_flags, [], %{top: nil, left: nil}}, fn
        {:style, value}, {flags, styles, scroll}
        when is_binary(value) or is_map(value) or is_list(value) ->
          {flags, [value | styles], scroll}

        {:scroll_y, top}, {flags, styles, scroll} when is_integer(top) ->
          {flags, styles, %{scroll | top: top}}

        {:scroll_x, left}, {flags, styles, scroll} when is_integer(left) ->
          {flags, styles, %{scroll | left: left}}

        {:scroll, {top, left}}, {flags, styles, _scroll}
        when is_integer(top) and is_integer(left) ->
          {flags, styles, %{top: top, left: left}}

        {flag, value}, {flags, styles, scroll} when is_atom(flag) ->
          {Keyword.put(flags, flag, value), styles, scroll}

        _, acc ->
          acc
      end)

    {style_flags, Enum.reverse(style_modifiers), scroll_modifier}
  end

  defp parse_modifiers(_modifiers, style_flags),
    do: {style_flags, [], %{top: nil, left: nil}}

  defp merge_scroll_modifier(attributes, %{top: nil, left: nil}), do: attributes

  defp merge_scroll_modifier(attributes, %{top: top, left: left}) do
    {existing_top, existing_left} = Map.get(attributes, :scroll, {0, 0})

    top = if is_integer(top), do: max(top, 0), else: existing_top
    left = if is_integer(left), do: max(left, 0), else: existing_left

    Map.put(attributes, :scroll, {top, left})
  end

  defp maybe_resolve_intrinsic_inline_width(style, children, content, attributes) do
    if Map.get(attributes, :display) == :inline and Map.get(style, :overflow) == :hidden and
         Map.get(style, :width) in [nil, :auto] do
      Map.put(style, :width, intrinsic_inline_width(children, content))
    else
      style
    end
  end

  defp maybe_resolve_inline_child_widths(children, style, attributes) do
    if Map.get(attributes, :display) == :inline and Map.get(style, :overflow) == :hidden and
         Map.get(style, :width) not in [nil, :auto, :full] do
      Enum.map(children, &resolve_box_width/1)
    else
      children
    end
  end

  defp resolve_box_width(%Box{} = box) do
    children = Enum.map(box.children, &resolve_box_width/1)

    width =
      if is_integer(box.style.width),
        do: box.style.width,
        else: intrinsic_box_width(%{box | children: children})

    %{box | children: children, width: width}
  end

  defp intrinsic_inline_width(children, content) do
    content_width = intrinsic_content_width(content)
    child_width = Enum.reduce(children, 0, &(&2 + intrinsic_box_width(&1)))
    max(content_width + child_width, 0)
  end

  defp intrinsic_content_width(nil), do: 0

  defp intrinsic_content_width(content) when is_binary(content),
    do: BackBreeze.Utils.string_length(content)

  defp intrinsic_content_width(%{__struct__: BackBreeze.VirtualText} = content),
    do: content |> BackBreeze.TextLayout.source_metrics() |> elem(1)

  defp intrinsic_content_width([%{__struct__: BackBreeze.TextSpan} | _rest] = content),
    do: content |> BackBreeze.TextLayout.source_metrics() |> elem(1)

  defp intrinsic_content_width(_content), do: 0

  defp intrinsic_box_width(%Box{style: %{width: width}}) when is_integer(width), do: width

  defp intrinsic_box_width(%Box{style: %{display: :inline}, children: children, content: content}) do
    intrinsic_inline_width(children, content)
  end

  defp intrinsic_box_width(%Box{children: children, content: content}) do
    child_width =
      children
      |> Enum.map(&intrinsic_box_width/1)
      |> Enum.max(fn -> 0 end)

    max(intrinsic_content_width(content), child_width)
  end

  defp merge_live_acc(acc, child_acc, parent_id) do
    child_offset = acc.id + 1
    child_last_id = max_key(child_acc.elements)

    child_tree =
      if Map.get(acc, :render_tree?, false),
        do: shift_render_tree(Map.get(child_acc, :render_tree), child_offset)

    elements =
      Enum.reduce(child_acc.elements, acc.elements, fn {id, flags}, elements ->
        Map.put(elements, child_offset + id, flags)
      end)

    acc = %{
      acc
      | id: child_offset + child_last_id + 1,
        elements: elements,
        boxes: Map.merge(Map.get(acc, :boxes, %{}), Map.get(child_acc, :boxes, %{})),
        ids: Enum.reverse(child_acc.ids) ++ acc.ids,
        focusables: Enum.reverse(child_acc.focusables) ++ acc.focusables,
        live_dimensions: Map.get(acc, :live_dimensions, %{})
    }

    case child_tree do
      nil -> acc
      tree -> put_render_tree_child(acc, parent_id, {:tree, tree})
    end
  end

  defp maybe_attach_live_viewports(root_tag, root_children, opts) do
    case Keyword.get(opts, :live_view) do
      fun when is_function(fun, 2) ->
        Keyword.put(
          opts,
          :live_viewports,
          live_placeholder_viewports(root_tag, root_children, opts)
        )

      _ ->
        opts
    end
  end

  defp maybe_refresh_live_dimensions(root_tag, root_children, opts, acc) do
    case Keyword.get(opts, :live_view) do
      fun when is_function(fun, 2) ->
        root_dimensions = live_root_dimensions(root_tag, root_children, opts, acc.live_dimensions)

        if root_dimensions == %{} do
          acc
        else
          live_viewports =
            opts
            |> Keyword.put(:live_placeholder_dimensions, root_dimensions)
            |> then(&live_placeholder_viewports(root_tag, root_children, &1))

          %{acc | live_dimensions: shift_live_dimensions(acc.live_dimensions, live_viewports)}
        end

      _ ->
        acc
    end
  end

  defp live_placeholder_viewports(root_tag, root_children, opts) do
    placeholder_opts = Keyword.put(opts, :live_placeholder, true)

    {placeholder_acc, placeholder_box} =
      build_from_tree_nodes(root_tag, root_children, placeholder_opts)

    %{dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(placeholder_box, placeholder_opts)

    placeholder_acc.elements
    |> Enum.sort()
    |> Enum.zip(dimensions)
    |> Enum.reduce(%{}, fn {{_idx, flags}, dims}, acc ->
      if Keyword.get(flags, :__live_placeholder__) do
        Map.put(acc, Keyword.fetch!(flags, :id), dims)
      else
        acc
      end
    end)
  end

  defp live_root_dimensions(root_tag, root_children, opts, live_dimensions) do
    live_ids(root_tag, root_children, opts)
    |> Enum.reduce(%{}, fn id, acc ->
      case Map.get(live_dimensions, id) do
        %{width: width, height: height} = dims
        when is_integer(width) and width > 0 and is_integer(height) and height > 0 ->
          Map.put(acc, id, dims)

        _ ->
          acc
      end
    end)
  end

  defp live_ids(_root_tag, root_children, opts) do
    collect_live_ids(root_children, Keyword.get(opts, :live_prefix), [])
  end

  defp collect_live_ids(nodes, prefix, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn
      {:live, attrs}, acc ->
        [live_full_id(fetch_live_attr!(attrs, :id), live_prefix_opts(prefix)) | acc]

      {_tag, _attrs, children}, acc when is_list(children) ->
        collect_live_ids(children, prefix, acc)

      _other, acc ->
        acc
    end)
  end

  defp collect_live_ids(_nodes, _prefix, acc), do: acc

  defp live_prefix_opts(nil), do: []
  defp live_prefix_opts(prefix), do: [live_prefix: prefix]

  defp shift_live_dimensions(live_dimensions, live_viewports) do
    Enum.reduce(live_viewports, live_dimensions, fn {id, next_root}, acc ->
      case Map.get(acc, id) do
        nil ->
          acc

        previous_root ->
          dx = Map.get(next_root, :left, 0) - Map.get(previous_root, :left, 0)
          dy = Map.get(next_root, :top, 0) - Map.get(previous_root, :top, 0)

          Map.new(acc, fn {key, dims} ->
            if key == id or String.starts_with?(key, id <> "::") do
              {key, shift_live_dimension(key, id, dims, next_root, dx, dy)}
            else
              {key, dims}
            end
          end)
      end
    end)
  end

  defp shift_live_dimension(id, id, dims, next_root, _dx, _dy) do
    Map.merge(dims, Map.take(next_root, dimension_keys()))
  end

  defp shift_live_dimension(_key, _id, dims, _next_root, dx, dy) do
    dims
    |> Map.update(:left, dx, &(&1 + dx))
    |> Map.update(:top, dy, &(&1 + dy))
  end

  defp dimension_keys do
    [
      :left,
      :top,
      :width,
      :height,
      :viewport_width,
      :viewport_height,
      :content_width,
      :content_height
    ]
  end

  defp build_live_placeholder(attrs, flags, acc, opts, current_id) do
    live_flags =
      [__live_placeholder__: true]
      |> inherit_implicit_owner(flags)
      |> inherit_focus_scope_path(flags)

    child_id = acc.id + 1

    acc =
      %{
        acc
        | flags: live_flags,
          id: child_id,
          elements: Map.put(acc.elements, acc.id, acc.flags)
      }
      |> put_render_tree_child(current_id, {:id, child_id})

    nodes = live_placeholder_nodes(attrs, opts)

    build_tree(
      nodes,
      %BackBreeze.Box{},
      [],
      RenderStyle.empty(),
      live_flags,
      acc,
      opts,
      child_id,
      :box
    )
  end

  defp live_placeholder_nodes(attrs, opts) do
    id = fetch_live_attr!(attrs, :id)
    full_id = live_full_id(id, opts)

    base = [{:attribute, ["id", full_id]}]

    nodes =
      attrs
      |> Enum.reduce(base, fn
        {key, value}, acc when key in [:class, "class"] and not is_nil(value) ->
          acc ++ [{:attribute, ["class", value]}]

        {key, value}, acc when key in [:style, "style"] and not is_nil(value) ->
          acc ++ [{:attribute, ["style", value]}]

        {key, true}, acc when key in [:focusable, "focusable"] ->
          acc ++ [{:attribute_bool, ["focusable"]}]

        _, acc ->
          acc
      end)

    case live_placeholder_dimension_style(full_id, opts) do
      nil -> nodes
      style -> nodes ++ [{:attribute, ["style", style]}]
    end
  end

  defp live_placeholder_dimension_style(full_id, opts) do
    dimensions = Keyword.get(opts, :live_placeholder_dimensions, %{})

    case Map.get(dimensions, full_id) do
      %{width: width, height: height}
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 ->
        %{width: width, height: height}

      _ ->
        nil
    end
  end

  defp live_full_id(id, opts) do
    case Keyword.get(opts, :live_prefix) do
      nil -> id
      prefix -> prefix <> "::" <> id
    end
  end

  defp maybe_put_live_terminal(opts, %{width: width, height: height} = viewport) do
    terminal = Keyword.get(opts, :terminal)

    width =
      resolve_live_terminal_dimension(width, Map.get(viewport, :viewport_width), terminal, :width)

    height =
      resolve_live_terminal_dimension(
        height,
        Map.get(viewport, :viewport_height),
        terminal,
        :height
      )

    if is_integer(width) and width > 0 and is_integer(height) and height > 0 do
      Keyword.put(opts, :live_terminal, resize_terminal(terminal, width, height))
    else
      opts
    end
  end

  defp maybe_put_live_terminal(opts, _viewport), do: opts

  defp resolve_live_terminal_dimension(primary, _secondary, _terminal, _axis)
       when is_integer(primary) and primary > 0,
       do: primary

  defp resolve_live_terminal_dimension(_primary, secondary, _terminal, _axis)
       when is_integer(secondary) and secondary > 0,
       do: secondary

  defp resolve_live_terminal_dimension(primary, _secondary, %Termite.Terminal{size: size}, :width)
       when primary in [:full, :screen],
       do: size.width

  defp resolve_live_terminal_dimension(
         primary,
         _secondary,
         %Termite.Terminal{size: size},
         :height
       )
       when primary in [:full, :screen],
       do: size.height

  defp resolve_live_terminal_dimension(_primary, _secondary, _terminal, _axis), do: nil

  defp resize_terminal(%Termite.Terminal{} = terminal, width, height) do
    %{terminal | size: %{width: width, height: height}}
  end

  defp resize_terminal(nil, width, height) do
    %Termite.Terminal{size: %{width: width, height: height}}
  end

  defp fetch_live_attr!(attrs, key) do
    case fetch_live_attr(attrs, key, nil) do
      nil -> raise KeyError, key: key, term: attrs
      value -> value
    end
  end

  defp fetch_live_attr(attrs, key, default) do
    cond do
      Keyword.keyword?(attrs) -> Keyword.get(attrs, key, default)
      is_map(attrs) -> Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
      true -> default
    end
  end

  defp normalize_animation_result({:ok, %Box{} = box, _opts}), do: {box, %{}}
  defp normalize_animation_result({:ok, %Box{} = box}), do: {box, %{}}
  defp normalize_animation_result(%Box{} = box), do: {box, %{}}

  defp maybe_dim_screen_backdrop(
         %{layer_map: layer_map} = box,
         acc,
         dimensions,
         _root_children,
         opts
       )
       when is_map(layer_map) and map_size(layer_map) > 0 do
    theme = Theme.new(Keyword.get(opts, :theme_source, Keyword.get(opts, :theme)))

    if screen_dimming_supported?(theme) do
      regions = screen_dim_regions(acc, dimensions)

      if regions == [] do
        box
      else
        background = Theme.resolve_color(theme, :background_color)
        layer_map = dim_layer_map_outside_regions(box.layer_map, regions, background, 0.45)

        %{
          box
          | layer_map: layer_map,
            content: Box.layer_map_to_content(layer_map, box.width, box.height)
        }
      end
    else
      box
    end
  end

  defp maybe_dim_screen_backdrop(box, _acc, _dimensions, _root_children, _opts), do: box

  defp screen_dimming_supported?(theme) do
    case theme.mode do
      :system16 -> false
      _ -> rgb_color?(Theme.resolve_color(theme, :background_color))
    end
  end

  defp screen_dim_regions(acc, dimensions) do
    resolved_dimensions =
      acc.elements
      |> Enum.sort()
      |> Enum.zip(dimensions)
      |> Enum.reduce(%{}, fn {{_idx, flags}, dims}, resolved ->
        case Keyword.get(flags, :id) do
          nil -> resolved
          id -> Map.put(resolved, id, dims)
        end
      end)
      |> Map.merge(Map.get(acc, :live_dimensions, %{}))

    Enum.flat_map(acc.elements, fn {_idx, flags} ->
      id = Keyword.get(flags, :id)

      if id && Keyword.get(flags, :"screen-dim") do
        case Map.get(resolved_dimensions, id) do
          nil ->
            []

          dims ->
            [
              %{
                left: Map.get(dims, :left, 0),
                top: Map.get(dims, :top, 0),
                right: Map.get(dims, :left, 0) + max(Map.get(dims, :width, 0) - 1, 0),
                bottom: Map.get(dims, :top, 0) + max(Map.get(dims, :height, 0) - 1, 0)
              }
            ]
        end
      else
        []
      end
    end)
  end

  defp dim_layer_map_outside_regions(layer_map, regions, background, amount) do
    {dimmed_map, _seq_cache} =
      Enum.reduce(layer_map, {%{}, %{}}, fn
        {key, value}, {acc, seq_cache} when key == :__wide_glyphs__ ->
          {Map.put(acc, key, value), seq_cache}

        {key, value}, {acc, seq_cache} when key == :__default_fill__ ->
          {Map.put(acc, key, value), seq_cache}

        {{y, x} = key, {char, seq}}, {acc, seq_cache} ->
          if point_in_any_region?(x, y, regions) do
            {Map.put(acc, key, {char, seq}), seq_cache}
          else
            {dimmed_seq, seq_cache} = dim_ansi_sequence(seq, background, amount, seq_cache)
            {Map.put(acc, key, {char, dimmed_seq}), seq_cache}
          end
      end)

    dimmed_map
  end

  defp point_in_any_region?(x, y, regions) do
    Enum.any?(regions, fn region ->
      x >= region.left and x <= region.right and y >= region.top and y <= region.bottom
    end)
  end

  defp dim_ansi_sequence(seq, _background, _amount, cache) when seq in ["", nil] do
    {seq || "", cache}
  end

  defp dim_ansi_sequence(seq, background, amount, cache) do
    case cache do
      %{^seq => dimmed_seq} ->
        {dimmed_seq, cache}

      _ ->
        dimmed_seq = dim_ansi_sgr_sequence(seq, background, amount)

        {dimmed_seq, Map.put(cache, seq, dimmed_seq)}
    end
  end

  defp dim_ansi_sgr_sequence(seq, background, amount) do
    Regex.replace(~r/\e\[([0-9;]+)m/, seq, fn _, params ->
      params =
        params
        |> String.split(";", trim: true)
        |> dim_sgr_params(background, amount, [])
        |> Enum.join(";")

      "\e[" <> params <> "m"
    end)
  end

  defp dim_sgr_params(["38", "2", red, green, blue | rest], background, amount, acc) do
    {dim_red, dim_green, dim_blue} =
      Theme.blend(
        {String.to_integer(red), String.to_integer(green), String.to_integer(blue)},
        background,
        amount
      )

    dim_sgr_params(
      rest,
      background,
      amount,
      acc ++
        [
          "38",
          "2",
          Integer.to_string(dim_red),
          Integer.to_string(dim_green),
          Integer.to_string(dim_blue)
        ]
    )
  end

  defp dim_sgr_params(["48", "2", red, green, blue | rest], background, amount, acc) do
    {dim_red, dim_green, dim_blue} =
      Theme.blend(
        {String.to_integer(red), String.to_integer(green), String.to_integer(blue)},
        background,
        amount
      )

    dim_sgr_params(
      rest,
      background,
      amount,
      acc ++
        [
          "48",
          "2",
          Integer.to_string(dim_red),
          Integer.to_string(dim_green),
          Integer.to_string(dim_blue)
        ]
    )
  end

  defp dim_sgr_params([param | rest], background, amount, acc) do
    dim_sgr_params(rest, background, amount, acc ++ [param])
  end

  defp dim_sgr_params([], _background, _amount, acc), do: acc

  defp rgb_color?({red, green, blue}) when red in 0..255 and green in 0..255 and blue in 0..255,
    do: true

  defp rgb_color?(_), do: false

  defp namespace_live_acc(acc, prefix, opts) do
    live_focus_within_path = Keyword.get(opts, :live_focus_within_path, [])

    acc
    |> Map.put(:ids, namespace_ids(acc.ids, prefix))
    |> Map.put(:focusables, namespace_ids(acc.focusables, prefix))
    |> Map.put(:boxes, namespace_box_map(Map.get(acc, :boxes, %{}), prefix))
    |> Map.put(:elements, namespace_elements(acc.elements, prefix, live_focus_within_path))
  end

  defp inherit_implicit_owner(child_flags, flags) do
    cond do
      Keyword.get(flags, :implicit) ->
        Keyword.put(child_flags, :implicit_owner, Keyword.fetch!(flags, :id))

      implicit_owner = Keyword.get(flags, :implicit_owner) ->
        Keyword.put(child_flags, :implicit_owner, implicit_owner)

      true ->
        child_flags
    end
  end

  defp inherit_selected_owner_value(child_flags, flags) do
    cond do
      value = Keyword.get(flags, :value) ->
        Keyword.put(child_flags, :selected_owner_value, value)

      value = Keyword.get(flags, :selected_owner_value) ->
        Keyword.put(child_flags, :selected_owner_value, value)

      true ->
        child_flags
    end
  end

  defp inherit_selected_with_owner(child_flags, opts) do
    if owner_selected?(child_flags, opts) do
      Keyword.put(child_flags, :selected, true)
    else
      child_flags
    end
  end

  defp owner_selected?(flags, opts) do
    implicit_state = Keyword.get(opts, :implicit_state, %{})
    implicit_owner = Keyword.get(flags, :implicit_owner)

    with true <- Keyword.has_key?(flags, :"selected-with-owner"),
         owner when not is_nil(owner) <- implicit_owner,
         owner_value when not is_nil(owner_value) <- Keyword.get(flags, :selected_owner_value),
         {_mod, implicit} <- Map.get(implicit_state, owner),
         true <- Map.get(implicit, :selected) == owner_value do
      true
    else
      _ -> false
    end
  end

  defp inherit_focus_scope_path(child_flags, flags) do
    scope_path = Keyword.get(flags, :"focus-scope-path", [])

    scope_path =
      if Keyword.get(flags, :"focus-scope") && Keyword.get(flags, :id) do
        scope_path ++ [Keyword.fetch!(flags, :id)]
      else
        scope_path
      end

    if scope_path == [],
      do: child_flags,
      else: Keyword.put(child_flags, :"focus-scope-path", scope_path)
  end

  defp inherit_focus_within_path(child_flags, flags) do
    focus_within_path = Keyword.get(flags, :"focus-within-path", [])

    focus_within_path =
      case Keyword.get(flags, :id) do
        id when is_binary(id) -> focus_within_path ++ [id]
        _ -> focus_within_path
      end

    if focus_within_path == [],
      do: child_flags,
      else: Keyword.put(child_flags, :"focus-within-path", focus_within_path)
  end

  defp namespace_id(nil, _prefix), do: nil
  defp namespace_id(id, prefix), do: prefix <> "::" <> id

  defp namespace_ids(ids, prefix), do: Enum.map(ids, &namespace_id(&1, prefix))

  defp namespace_box_map(boxes, prefix) do
    Map.new(boxes, fn {id, box} ->
      namespaced_id =
        case id do
          id when is_binary(id) -> namespace_id(id, prefix)
          other -> other
        end

      {namespaced_id, box}
    end)
  end

  defp namespace_elements(elements, prefix, live_focus_within_path) do
    Map.new(elements, fn {idx, flags} ->
      {idx, namespace_element_flags(flags, prefix, live_focus_within_path)}
    end)
  end

  defp namespace_element_flags(flags, prefix, live_focus_within_path) do
    flags
    |> Keyword.update(:id, nil, &namespace_id(&1, prefix))
    |> Keyword.update(:implicit_owner, nil, &namespace_id(&1, prefix))
    |> Keyword.update(:"focus-scope-path", [], &namespace_ids(&1, prefix))
    |> Keyword.update(:"focus-within-path", live_focus_within_path ++ [prefix], fn path ->
      live_focus_within_path ++ [prefix | namespace_ids(path, prefix)]
    end)
  end

  defp focus_within_path(flags) do
    inherited = Keyword.get(flags, :"focus-within-path", [])

    case Keyword.get(flags, :id) do
      id when is_binary(id) -> inherited ++ [id]
      _ -> inherited
    end
  end

  defp focused_within?(flags, root_id, focused_target, acc) do
    focus_within_target = focus_within_target(flags, root_id)

    Keyword.get(flags, :"focus-within") in [true, "true"] and is_binary(focus_within_target) and
      focused_descends_from?(focused_target, focus_within_target, acc)
  end

  defp focus_within_target(_flags, root_id) when is_binary(root_id), do: root_id

  defp focus_within_target(flags, _root_id) do
    flags
    |> Keyword.get(:"focus-within-path", [])
    |> List.last()
  end

  defp focused_descends_from?(nil, _root_id, _acc), do: false

  defp focused_descends_from?(focused_target, root_id, acc) do
    case focused_element_flags(focused_target, acc) do
      nil ->
        false

      focused_flags ->
        root_id in Keyword.get(focused_flags, :"focus-within-path", [])
    end
  end

  defp focused_element_flags(focused_target, acc) do
    [Map.get(acc, :flags) | Enum.map(Map.get(acc, :elements, %{}), fn {_idx, flags} -> flags end)]
    |> Enum.find_value(fn
      nil ->
        nil

      {_idx, flags} ->
        if Keyword.get(flags, :id) == focused_target, do: flags

      flags ->
        if Keyword.get(flags, :id) == focused_target, do: flags
    end)
  end

  defp animation_ctx(opts, id, focused, previous_layout) do
    %{
      phase: Keyword.get(opts, :animation_phase, :base),
      frame: Keyword.get(opts, :animation_frame, 0),
      now: Keyword.get(opts, :animation_now),
      pending?: Keyword.get(opts, :animation_pending?, false),
      focused?: focused,
      last_render_at: Keyword.get(opts, :last_render_at),
      last_interaction_at: Keyword.get(opts, :last_interaction_at),
      id: id,
      layout: previous_layout
    }
  end

  defp max_key(elements) do
    elements
    |> Map.keys()
    |> Enum.max(fn -> 0 end)
  end

  defp virtual_text_surface?(%{__struct__: BackBreeze.VirtualText}), do: true
  defp virtual_text_surface?(_value), do: false

  defp text_span_list?([%{__struct__: BackBreeze.TextSpan} | _rest]), do: true
  defp text_span_list?(_value), do: false

  defp profile(nil, _label, _metric, fun), do: fun.()

  defp profile(scope, label, metric, fun) do
    :telemetry.span(
      [:breeze, :render],
      %{scope: scope, label: label, metric: metric},
      fn ->
        result = fun.()
        {result, %{scope: scope, label: label, metric: metric}}
      end
    )
  end

  defp emit_metric(nil, _label, _metric, _value), do: :ok

  defp emit_metric(scope, label, metric, value) do
    :telemetry.execute(
      [:breeze, :render, :metric],
      %{value: value},
      %{scope: scope, label: label, metric: metric}
    )
  end
end
