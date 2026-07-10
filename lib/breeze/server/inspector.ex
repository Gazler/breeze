defmodule Breeze.Server.Inspector do
  @moduledoc false

  def picks_mouse?(state), do: Breeze.Inspector.picks_mouse?(state)

  def select_target(state, %{button: :left, action: :press} = event) do
    Breeze.Inspector.select_at(state, event)
  end

  def select_target(state, %{action: :move} = event) do
    Breeze.Inspector.hover_at(state, event)
  end

  def select_target(state, _event), do: state

  def toggle_key?(key, state) do
    Breeze.Inspector.enabled?(state) and key == Breeze.Inspector.toggle_key(state)
  end

  def move_key?(key, state) do
    Breeze.Inspector.enabled?(state) and state.inspector_state.visible? and
      key == Breeze.Inspector.move_key(state)
  end

  def merge_render_data(%{inspector_state: %{config: false}} = state, _acc, _metadata), do: state

  def merge_render_data(state, acc, metadata) do
    %{
      viewports: viewports,
      bounds: bounds,
      flags: flags,
      boxes: boxes,
      tree_meta: tree_meta,
      code_tree_meta: code_tree_meta
    } = nodes(acc, state.theme)

    state
    |> update_rendered(
      viewports: viewports,
      mouse_targets: bounds,
      flags: flags,
      boxes: Map.merge(state.rendered.boxes, boxes),
      render_tree: Map.get(acc, :render_tree),
      render_tree_meta: tree_meta,
      code_tree_meta: code_tree_meta,
      focus_meta: Map.get(metadata, :focus_meta, %{}),
      implicit_state: Map.get(metadata, :implicit_state, %{}),
      implicit_meta: Map.get(metadata, :implicit_meta, %{})
    )
    |> Breeze.Inspector.sync_selected_id()
  end

  def push_snapshot_now(%{inspector_state: %{config: false}} = state), do: state

  def push_snapshot_now(%{inspector_state: %{subscribers: subscribers}} = state) do
    snapshot = Breeze.Inspector.snapshot(state)

    if Breeze.Inspector.remote?(state) do
      Breeze.RemoteInspector.publish(snapshot)
    end

    if MapSet.size(subscribers) > 0 do
      Enum.each(subscribers, fn subscriber ->
        if is_pid(subscriber), do: send(subscriber, {:inspector_snapshot, snapshot})
      end)
    end

    state
  end

  defp update_rendered(state, updates), do: %{state | rendered: struct!(state.rendered, updates)}

  defp nodes(acc, theme) do
    source_boxes = Map.get(acc, :boxes, %{})

    acc.elements
    |> Enum.sort()
    |> Enum.zip(acc.dimensions)
    |> Enum.reduce(
      %{viewports: %{}, bounds: %{}, flags: %{}, boxes: %{}, tree_meta: %{}, code_tree_meta: %{}},
      fn {{idx, flags}, dims}, node_acc ->
        key = node_key(idx, flags)
        box = node_box(source_boxes, idx, flags)
        viewport = Breeze.Viewport.from_dimensions(dims)

        width = max((viewport.width || 0) - 1, 0)
        height = max(viewport.height - 1, 0)
        normalized_flags = Keyword.put(flags, :__inspector_idx__, idx)

        bounds = %{
          left: viewport.left,
          top: viewport.top,
          right: viewport.left + width,
          bottom: viewport.top + height
        }

        %{
          viewports: Map.put(node_acc.viewports, key, viewport),
          bounds: Map.put(node_acc.bounds, key, bounds),
          flags: Map.put(node_acc.flags, key, normalized_flags),
          boxes: put_node_box(node_acc.boxes, key, box),
          tree_meta:
            Map.put(
              node_acc.tree_meta,
              idx,
              render_tree_meta(idx, key, normalized_flags, viewport, bounds, box, theme)
            ),
          code_tree_meta:
            Map.put(
              node_acc.code_tree_meta,
              idx,
              code_tree_meta(idx, key, normalized_flags, box, theme)
            )
        }
      end
    )
  end

  defp render_tree_meta(idx, key, flags, viewport, bounds, box, theme) do
    tag = "box"

    %{
      id: key,
      actual_id: Keyword.get(flags, :id),
      inspector_idx: idx,
      label: render_tree_label(tag, idx, key, flags, box, theme),
      label_parts: render_tree_label_parts(tag, idx, key, flags, box, theme),
      tag: tag,
      component: Keyword.get(flags, :"breeze-component"),
      class: Keyword.get(flags, :class),
      style_input: Keyword.get(flags, :style_input),
      implicit: Keyword.get(flags, :implicit),
      focusable?: Keyword.get(flags, :focusable, false),
      focused?: Keyword.get(flags, :focused, false),
      selected?: Keyword.get(flags, :selected, false),
      bounds: bounds,
      layout: %{
        left: viewport.left,
        top: viewport.top,
        width: viewport.width || 0,
        height: viewport.height
      }
    }
  end

  defp code_tree_meta(idx, key, flags, box, theme) do
    tag = code_tree_tag(flags)

    %{
      id: key,
      actual_id: Keyword.get(flags, :id),
      inspector_idx: idx,
      label: code_tree_label(tag, idx, key, flags, box, theme),
      label_parts: code_tree_label_parts(tag, idx, key, flags, box, theme),
      tag: tag,
      component: Keyword.get(flags, :"breeze-component"),
      class: Keyword.get(flags, :class),
      style_input: Keyword.get(flags, :style_input),
      implicit: Keyword.get(flags, :implicit),
      focusable?: Keyword.get(flags, :focusable, false),
      focused?: Keyword.get(flags, :focused, false),
      selected?: Keyword.get(flags, :selected, false),
      tree_kind: :code
    }
  end

  defp code_tree_tag(flags) do
    case Keyword.get(flags, :"breeze-component") do
      component when is_binary(component) -> component
      _ -> "box"
    end
  end

  defp render_tree_label(tag, idx, key, flags, box, theme) do
    tag
    |> render_tree_label_parts(idx, key, flags, box, theme)
    |> Enum.map(& &1.text)
    |> IO.iodata_to_binary()
  end

  defp code_tree_label(tag, idx, key, flags, box, theme) do
    tag
    |> code_tree_label_parts(idx, key, flags, box, theme)
    |> Enum.map(& &1.text)
    |> IO.iodata_to_binary()
  end

  defp render_tree_label_parts(tag, idx, key, flags, box, theme) do
    id = Keyword.get(flags, :id)
    component = Keyword.get(flags, :"breeze-component")

    [
      %{text: "<", token: :punctuation},
      %{text: tag, token: :tag},
      render_tree_id_part(id, key, idx),
      render_tree_class_parts(Keyword.get(flags, :class), box, flags, theme),
      render_tree_style_input_swatch_parts(box, flags, theme),
      %{text: ">", token: :punctuation},
      render_tree_component_part(component)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp code_tree_label_parts(tag, idx, key, flags, box, theme) do
    [
      %{text: "<", token: :punctuation},
      %{text: tag, token: :tag},
      render_tree_id_part(Keyword.get(flags, :id), key, idx),
      render_tree_class_parts(Keyword.get(flags, :class), box, flags, theme),
      render_tree_style_input_swatch_parts(box, flags, theme),
      %{text: ">", token: :punctuation}
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp render_tree_id_part(id, _key, _idx) when is_binary(id) do
    %{text: "#" <> id, token: :id}
  end

  defp render_tree_id_part(_id, _key, idx) do
    %{text: " anon#" <> Integer.to_string(idx), token: :anonymous_id}
  end

  defp render_tree_class_parts(class, %BackBreeze.Box{} = box, flags, theme)
       when is_binary(class) do
    style = normalize_style_map(box.style)

    class
    |> String.split()
    |> Enum.take(3)
    |> Enum.flat_map(fn token ->
      [
        %{text: "." <> token, token: :class},
        render_tree_class_swatch_part(token, flags, style, theme)
      ]
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp render_tree_class_parts(_class, _box, _flags, _theme), do: []

  defp render_tree_component_part(component) when is_binary(component) do
    %{text: " " <> component, token: :component}
  end

  defp render_tree_component_part(_component), do: nil

  defp render_tree_style_input_swatch_parts(%BackBreeze.Box{} = box, flags, theme) do
    intents =
      MapSet.new()
      |> collect_class_color_intents(Keyword.get(flags, :style_input), flags, theme)
      |> collect_style_map_color_intents(Keyword.get(flags, :style_input))

    style = normalize_style_map(box.style)
    fg = if MapSet.member?(intents, :foreground), do: Map.get(style, :foreground_color)
    bg = if MapSet.member?(intents, :background), do: Map.get(style, :background_color)

    cond do
      recognized_color?(fg) and recognized_color?(bg) ->
        [
          %{text: " ", token: :separator},
          swatch_part(:foreground, fg),
          swatch_part(:background, bg)
        ]

      recognized_color?(fg) ->
        [%{text: " ", token: :separator}, swatch_part(:foreground, fg)]

      recognized_color?(bg) ->
        [%{text: " ", token: :separator}, swatch_part(:background, bg)]

      true ->
        []
    end
  end

  defp render_tree_style_input_swatch_parts(_box, _flags, _theme), do: []

  defp render_tree_class_swatch_part(token, flags, style, theme) do
    with {active?, active_token} <- style_token_state(token, flags),
         role when role in [:foreground, :background] <- color_token_role(active_token),
         color when not is_nil(color) <- swatch_color(active_token, role, style, theme, active?),
         true <- recognized_color?(color) do
      swatch_part(role, color)
    else
      _ -> nil
    end
  end

  defp swatch_part(:foreground, color) do
    %{
      text: "●",
      token: :swatch,
      role: :foreground,
      foreground_color: color,
      background_color: nil
    }
  end

  defp swatch_part(:background, color) do
    %{
      text: "●",
      token: :swatch,
      role: :background,
      foreground_color: color,
      background_color: nil
    }
  end

  defp color_for_role(style, :foreground), do: Map.get(style, :foreground_color)
  defp color_for_role(style, :background), do: Map.get(style, :background_color)

  defp swatch_color(token, role, style, theme, true) do
    resolve_token_color(token, role, theme) || color_for_role(style, role)
  end

  defp swatch_color(token, role, _style, theme, false) do
    resolve_token_color(token, role, theme)
  end

  defp resolve_token_color("text", :foreground, theme),
    do: Breeze.Theme.resolve_color(theme, :text)

  defp resolve_token_color("text-" <> color, :foreground, theme),
    do: Breeze.Theme.resolve_color(theme, color)

  defp resolve_token_color("placeholder-text", :foreground, theme),
    do: Breeze.Theme.resolve_color(theme, :text)

  defp resolve_token_color("placeholder-text-" <> color, :foreground, theme),
    do: Breeze.Theme.resolve_color(theme, color)

  defp resolve_token_color("bg", :background, theme),
    do: Breeze.Theme.resolve_color(theme, :background)

  defp resolve_token_color("bg-" <> color, :background, theme),
    do: Breeze.Theme.resolve_color(theme, color)

  defp resolve_token_color(_token, _role, _theme), do: nil

  defp color_token_role("text"), do: :foreground
  defp color_token_role("text-" <> _color), do: :foreground
  defp color_token_role("mute-text-" <> _value), do: :foreground
  defp color_token_role("emphasize-text-" <> _value), do: :foreground
  defp color_token_role("placeholder-text"), do: :foreground
  defp color_token_role("placeholder-text-" <> _color), do: :foreground
  defp color_token_role("bg"), do: :background
  defp color_token_role("bg-" <> _color), do: :background
  defp color_token_role("mute-bg-" <> _value), do: :background
  defp color_token_role("emphasize-bg-" <> _value), do: :background
  defp color_token_role(_token), do: nil

  defp collect_class_color_intents(intents, value, flags, theme) do
    value
    |> class_tokens()
    |> Enum.reduce(intents, fn token, intents ->
      case style_token_state(token, flags) do
        {_active?, token} -> collect_color_token_intent(intents, token, theme)
        nil -> intents
      end
    end)
  end

  defp collect_color_token_intent(intents, token, theme) do
    case color_token_role(token) do
      :foreground ->
        if recognized_color?(resolve_token_color(token, :foreground, theme)),
          do: MapSet.put(intents, :foreground),
          else: intents

      :background ->
        if recognized_color?(resolve_token_color(token, :background, theme)),
          do: MapSet.put(intents, :background),
          else: intents

      nil ->
        intents
    end
  end

  defp collect_style_map_color_intents(intents, value) when is_map(value) do
    Enum.reduce(value, intents, fn {key, _value}, intents ->
      case normalize_color_style_key(key) do
        key when key in [:foreground_color, :text] -> MapSet.put(intents, :foreground)
        key when key in [:background_color, :bg] -> MapSet.put(intents, :background)
        _key -> intents
      end
    end)
  end

  defp collect_style_map_color_intents(intents, value) when is_list(value) do
    if Keyword.keyword?(value) do
      collect_style_map_color_intents(intents, Map.new(value))
    else
      Enum.reduce(value, intents, &collect_style_map_color_intents(&2, &1))
    end
  end

  defp collect_style_map_color_intents(intents, _value), do: intents

  defp normalize_color_style_key(key) when is_atom(key), do: key

  defp normalize_color_style_key(key) when is_binary(key) do
    case key |> String.trim() |> String.replace("-", "_") do
      "foreground_color" -> :foreground_color
      "background_color" -> :background_color
      "text" -> :text
      "bg" -> :bg
      _key -> key
    end
  end

  defp normalize_color_style_key(key), do: key

  defp class_tokens(value) when is_list(value) do
    if Keyword.keyword?(value) do
      class_tokens(Map.new(value))
    else
      value
      |> Enum.reverse()
      |> Enum.flat_map(&class_tokens/1)
    end
  end

  defp class_tokens(value) do
    value
    |> class_segments()
    |> Enum.flat_map(&String.split(&1, " ", trim: true))
  end

  defp class_segments(nil), do: []
  defp class_segments(false), do: []
  defp class_segments(value) when is_binary(value), do: [String.trim(value)]
  defp class_segments(value) when is_atom(value), do: [Atom.to_string(value)]
  defp class_segments(value) when is_list(value), do: Enum.flat_map(value, &class_segments/1)
  defp class_segments(value) when is_integer(value), do: [Integer.to_string(value)]
  defp class_segments(value) when is_float(value), do: [Float.to_string(value)]

  defp class_segments(value) when is_map(value) do
    value
    |> Enum.flat_map(fn
      {key, true} ->
        class_segments(key)

      {_key, truthy} when truthy in [false, nil] ->
        []

      {key, nested_value} ->
        case class_segments(nested_value) do
          [] -> []
          nested_segments -> [Enum.join(class_segments(key) ++ nested_segments, "-")]
        end
    end)
  end

  defp class_segments(_value), do: []

  defp style_token_state(token, flags) do
    token
    |> String.split(":")
    |> Enum.reduce_while({true, nil, false}, fn
      "focus", {active?, _token, placeholder?} ->
        {:cont, {active? and Keyword.get(flags, :focused, false), nil, placeholder?}}

      "selected", {active?, _token, placeholder?} ->
        {:cont, {active? and Keyword.get(flags, :selected, false), nil, placeholder?}}

      "placeholder", {active?, _token, _placeholder?} ->
        placeholder_active? =
          Keyword.get(flags, :placeholder, false) or
            Keyword.get(flags, :__live_placeholder__, false)

        {:cont, {active? and placeholder_active?, nil, true}}

      token, {active?, _token, placeholder?} ->
        {:halt, {active?, token, placeholder?}}
    end)
    |> case do
      {_active?, nil, _placeholder?} -> nil
      {active?, token, true} -> {active?, "placeholder-" <> token}
      {active?, token, false} -> {active?, token}
    end
  end

  defp normalize_style_map(%{__struct__: _struct} = style), do: Map.from_struct(style)
  defp normalize_style_map(style) when is_map(style), do: style
  defp normalize_style_map(_style), do: %{}

  defp recognized_color?(color) when is_integer(color), do: color >= 0

  defp recognized_color?({r, g, b})
       when r in 0..255 and g in 0..255 and b in 0..255,
       do: true

  defp recognized_color?(_color), do: false

  defp node_key(idx, flags) do
    case Keyword.get(flags, :id) do
      id when is_binary(id) -> id
      _ -> "__inspector__" <> Integer.to_string(idx)
    end
  end

  defp node_box(source_boxes, idx, flags) do
    Map.get(source_boxes, Keyword.get(flags, :id)) || Map.get(source_boxes, idx)
  end

  defp put_node_box(boxes, key, box) do
    case Map.get(boxes, key) do
      nil ->
        if is_nil(box), do: boxes, else: Map.put(boxes, key, box)

      _box ->
        boxes
    end
  end
end
