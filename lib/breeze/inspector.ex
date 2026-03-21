defmodule Breeze.Inspector do
  @moduledoc false

  alias Breeze.Viewport

  @panel_height 11
  @max_preview_lines 2

  def panel_height, do: @panel_height

  def enabled?(%{inspector: false}), do: false
  def enabled?(%{inspector: nil}), do: false
  def enabled?(_state), do: true

  def config(state) do
    case Map.get(state, :inspector) do
      config when is_list(config) -> config
      true -> []
      _ -> []
    end
  end

  def toggle_key(state), do: Keyword.get(config(state), :toggle_key, "F4")
  def move_key(state), do: Keyword.get(config(state), :move_key, "PageUp")
  def panel_position(state), do: Map.get(state, :inspector_panel_position, :bottom)

  def picks_mouse?(state) do
    enabled?(state) and Map.get(state, :inspector_visible?, false)
  end

  def toggle(state) do
    visible? = not Map.get(state, :inspector_visible?, false)

    state
    |> Map.put(:inspector_visible?, visible?)
    |> Map.put(
      :inspector_selected_id,
      if(visible?, do: Map.get(state, :inspector_selected_id), else: nil)
    )
    |> Map.put(:inspector_hovered_id, nil)
    |> sync_selected_id()
  end

  def toggle_position(state) do
    next_position =
      case panel_position(state) do
        :top -> :bottom
        _ -> :top
      end

    Map.put(state, :inspector_panel_position, next_position)
  end

  def hover_at(state, %{x: x, y: y}) do
    if inside_panel?(state, x, y) do
      state
    else
      Map.put(state, :inspector_hovered_id, state |> targets_at(x, y) |> List.first())
    end
  end

  def select_at(state, %{x: x, y: y}) do
    if inside_panel?(state, x, y) do
      state
    else
      targets = targets_at(state, x, y)
      id = next_target(targets, Map.get(state, :inspector_selected_id))

      state
      |> Map.put(:inspector_selected_id, id)
      |> Map.put(:inspector_hovered_id, id)
      |> sync_selected_id()
    end
  end

  def sync_selected_id(state) do
    selected_id =
      case Map.get(state, :inspector_selected_id) do
        id when is_binary(id) ->
          if has_element?(state, id), do: id, else: fallback_selected_id(state)

        _ ->
          fallback_selected_id(state)
      end

    Map.put(state, :inspector_selected_id, selected_id)
  end

  def snapshot(state) do
    state = sync_selected_id(state)
    screen = Map.get(state.terminal, :size, %{width: 0, height: 0})
    selected_id = Map.get(state, :inspector_selected_id)
    hovered_id = Map.get(state, :inspector_hovered_id)

    %{
      enabled?: enabled?(state),
      visible?: Map.get(state, :inspector_visible?, false),
      selected_id: selected_id,
      hovered_id: hovered_id,
      focused: Map.get(state, :focused),
      root_view: Map.get(state, :view),
      theme: Map.get(state, :theme),
      screen: screen,
      toggle_key: toggle_key(state),
      move_key: move_key(state),
      panel_position: panel_position(state),
      hovered: selected_snapshot(state, hovered_id),
      selected: selected_snapshot(state, selected_id)
    }
  end

  def overlays(state) do
    snapshot = snapshot(state)

    if snapshot.visible? do
      hover_overlays(snapshot.hovered, snapshot.selected_id) ++
        selected_overlays(snapshot.selected) ++ panel_overlays(snapshot, state)
    else
      []
    end
  end

  defp targets_at(state, x, y) do
    state
    |> Map.get(:rendered_mouse_targets, %{})
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
    viewport = Map.get(state.rendered_viewports, id, %Viewport{})
    bounds = Map.get(state.rendered_mouse_targets, id, %{})
    flags = normalize_flags(Map.get(state.rendered_flags, id, []))
    actual_id = Map.get(flags, :id)
    box = Map.get(state.rendered_boxes, id)
    focus_meta = Map.get(state.rendered_focus_meta, id, %{})
    implicit_entry = Map.get(state.rendered_implicit_state, id)
    implicit_meta = Map.get(state.rendered_implicit_meta, id, %{})

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

    %{
      id: id,
      actual_id: actual_id,
      viewport: viewport,
      bounds: bounds,
      flags: flags,
      class: Map.get(flags, :class),
      style: resolved_style(box, flags, state.theme),
      focus_meta: focus_meta,
      implicit_module: implicit_module,
      implicit_state: implicit_state,
      implicit_meta: implicit_meta,
      fragment_preview: preview_fragment(fragment),
      content_box: content_box(viewport, box),
      padding: padding(box),
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
        state
        |> Map.get(:rendered_flags, %{})
        |> Enum.sort_by(fn {key, _flags} -> key end)
        |> Enum.find_value(fn {key, flags} ->
          case Map.get(Map.new(flags), :id) do
            nil -> nil
            _ -> key
          end
        end) ||
          state |> Map.get(:rendered_flags, %{}) |> Map.keys() |> Enum.sort() |> List.first()
    end
  end

  defp has_element?(state, id) when is_binary(id) do
    Map.has_key?(Map.get(state, :rendered_flags, %{}), id)
  end

  defp has_element?(_state, _id), do: false

  defp content_box(viewport, %BackBreeze.Box{} = box) do
    %{left: left_inset, right: right_inset, top: top_inset, bottom: bottom_inset} =
      inner_insets(box)

    %{
      left: viewport.left + left_inset,
      top: viewport.top + top_inset,
      width: max((viewport.width || 0) - left_inset - right_inset, 0),
      height: max(viewport.height - top_inset - bottom_inset, 0)
    }
  end

  defp content_box(viewport, _box) do
    %{left: viewport.left, top: viewport.top, width: viewport.width || 0, height: viewport.height}
  end

  defp padding(%BackBreeze.Box{style: style}) do
    %{
      top: style_value(style, :padding_top),
      right: style_value(style, :padding_right),
      bottom: style_value(style, :padding_bottom),
      left: style_value(style, :padding_left)
    }
  end

  defp padding(_box), do: %{top: 0, right: 0, bottom: 0, left: 0}

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

  defp border_inset(border, side) do
    if Map.get(border, side), do: 1, else: 0
  end

  defp style_value(style, key) do
    case Map.get(style, key) do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

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

  defp truncate(text, width) when is_integer(width) and width > 3 do
    if String.length(text) > width do
      String.slice(text, 0, width - 3) <> "..."
    else
      text
    end
  end

  defp truncate(text, _width), do: text
end
