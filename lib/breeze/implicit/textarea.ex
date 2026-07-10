defmodule Breeze.Implicit.Textarea do
  @moduledoc false

  @behaviour Breeze.Implicit

  alias BackBreeze.Ucwidth
  alias Breeze.Implicit.TextEditor
  alias Breeze.Theme

  def init(_items, root_attrs, last_state) do
    value = Map.get(root_attrs, :"textarea-value", "")

    cursor =
      case Map.fetch(root_attrs, :"textarea-cursor") do
        {:ok, nil} ->
          if Map.get(last_state, :value) == value and is_integer(Map.get(last_state, :cursor)) do
            Map.get(last_state, :cursor)
          else
            TextEditor.max_cursor(value)
          end

        {:ok, raw_cursor} ->
          if is_binary(raw_cursor), do: String.to_integer(raw_cursor), else: raw_cursor

        :error ->
          if Map.get(last_state, :value) == value and is_integer(Map.get(last_state, :cursor)) do
            Map.get(last_state, :cursor)
          else
            TextEditor.max_cursor(value)
          end
      end

    attrs_state = %{
      value: value,
      cursor: cursor,
      placeholder: Map.get(root_attrs, :"textarea-placeholder"),
      submit_on_enter?: submit_on_enter?(root_attrs),
      preferred_column: nil
    }

    state = Map.merge(last_state, attrs_state)
    state = TextEditor.normalize_state(state)

    {:ok, state,
     rerender_every: 500,
     active_when_focused: true,
     captures_printable_keys: true,
     requires_layout_rerender: true}
  end

  def handle_event(_, %{"key" => "\x7f"}, state), do: TextEditor.backspace(state)

  def handle_event(_, %{"key" => key}, %{cursor: cursor} = state)
      when key in ["\x08", "\x17"] and cursor > 0 do
    TextEditor.delete_previous_word(state)
  end

  def handle_event(_, %{"key" => key}, state) when key in ["\x08", "\x17"], do: {:noreply, state}

  def handle_event(_, %{"ctrlKey" => true, "key" => key}, %{cursor: cursor} = state)
      when key in ["Backspace", "w"] and cursor > 0 do
    TextEditor.delete_previous_word(state)
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => key}, state)
      when key in ["Backspace", "w"],
      do: {:noreply, state}

  def handle_event(_, %{"key" => "Delete"}, state) do
    TextEditor.delete_forward(state)
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "j"}, state),
    do: TextEditor.insert_newline(state)

  def handle_event(_, %{"shiftKey" => true, "key" => "Enter"}, state),
    do: TextEditor.insert_newline(state)

  def handle_event(_, %{"shiftKey" => true, "key" => "\n"}, state),
    do: TextEditor.insert_newline(state)

  def handle_event(_, %{"shiftKey" => true, "key" => "\r"}, state),
    do: TextEditor.insert_newline(state)

  def handle_event(_, %{"key" => "Enter"}, %{submit_on_enter?: true} = state),
    do: TextEditor.submit(state)

  def handle_event(_, %{"key" => "\n"}, %{submit_on_enter?: true} = state),
    do: TextEditor.submit(state)

  def handle_event(_, %{"key" => "\r"}, %{submit_on_enter?: true} = state),
    do: TextEditor.submit(state)

  def handle_event(_, %{"key" => "Enter"}, state), do: TextEditor.insert_newline(state)
  def handle_event(_, %{"key" => "\n"}, state), do: TextEditor.insert_newline(state)
  def handle_event(_, %{"key" => "\r"}, state), do: TextEditor.insert_newline(state)

  def handle_event(_, %{"key" => "ArrowLeft"}, %{cursor: cursor} = state) when cursor > 0 do
    TextEditor.move_left(state)
  end

  def handle_event(_, %{"key" => "ArrowLeft"}, state), do: {:noreply, state}

  def handle_event(_, %{"key" => "ArrowRight"}, state) do
    TextEditor.move_right(state)
  end

  def handle_event(_, %{"key" => "ArrowUp"}, state) do
    TextEditor.move_vertical(state, -1)
  end

  def handle_event(_, %{"key" => "ArrowDown"}, state) do
    TextEditor.move_vertical(state, 1)
  end

  def handle_event(_, %{"key" => "Home"}, state) do
    TextEditor.move_line_start(state)
  end

  def handle_event(_, %{"key" => "End"}, state) do
    TextEditor.move_line_end(state)
  end

  def handle_event(_, %{"key" => key} = event, state) do
    TextEditor.insert_key(key, event, state, allow_newline: true)
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, _flags, state), do: placeholder_modifiers(state)
  def handle_modifiers(:child, _flags, state), do: placeholder_modifiers(state)

  def animate(
        :root,
        box,
        _flags,
        state,
        %{layout: layout, now: now, last_interaction_at: last_interaction_at} = ctx
      )
      when is_map(layout) do
    layout = resolve_layout(layout, box)
    source = source_content(state)
    {content, cursor_x, cursor_y} = render_visible_content(source, state, layout, box)
    theme = Map.get(ctx, :theme)
    defaults = Theme.default_style(theme)

    overlay = %{
      x: layout.left + content_left_offset(box) + cursor_x,
      y: layout.top + content_top_offset(box) + cursor_y,
      char: cursor_char(content, cursor_y, cursor_x),
      foreground_color: Map.get(defaults, :background_color),
      background_color: Theme.color(theme, :cursor) || Theme.color(theme, :accent),
      visible?: Breeze.TerminalOverlay.visible?(now, last_interaction_at)
    }

    {:ok, %{box | content: content}, overlays: [overlay]}
  end

  def animate(
        :root,
        box,
        _flags,
        state,
        %{now: now, last_interaction_at: last_interaction_at} = ctx
      ) do
    case initial_layout(box) do
      nil ->
        box

      layout ->
        source = source_content(state)
        {content, cursor_x, cursor_y} = render_visible_content(source, state, layout, box)
        theme = Map.get(ctx, :theme)
        defaults = Theme.default_style(theme)

        overlay = %{
          x: content_left_offset(box) + cursor_x,
          y: content_top_offset(box) + cursor_y,
          char: cursor_char(content, cursor_y, cursor_x),
          foreground_color: Map.get(defaults, :background_color),
          background_color: Theme.color(theme, :cursor) || Theme.color(theme, :accent),
          visible?: Breeze.TerminalOverlay.visible?(now, last_interaction_at)
        }

        {:ok, %{box | content: content}, overlays: [overlay]}
    end
  end

  def animate(:root, box, _flags, _state, _ctx), do: box
  def animate(:child, box, _flags, _state, _ctx), do: box

  defp submit_on_enter?(attrs) do
    truthy?(Map.get(attrs, :"textarea-submit-on-enter")) or Map.has_key?(attrs, :"br-submit")
  end

  defp truthy?(value), do: value in [true, "true", ""]

  defp source_content(%{value: "", placeholder: placeholder})
       when is_binary(placeholder) and placeholder != "" do
    placeholder
  end

  defp source_content(%{value: value}), do: value

  defp placeholder_modifiers(%{value: "", placeholder: placeholder})
       when is_binary(placeholder) and placeholder != "" do
    [placeholder: true]
  end

  defp placeholder_modifiers(_state), do: []

  defp render_visible_content(content, state, layout, box) when is_binary(content) do
    width = content_viewport_width(layout.viewport_width, box)
    height = content_viewport_height(layout.viewport_height, box)
    {lines, cursor_row, cursor_x} = wrap_lines(content, state, width)
    scroll_top = scroll_top(cursor_row, height, length(lines))
    visible_lines = lines |> Enum.slice(scroll_top, height) |> Enum.join("\n")
    visible_cursor_y = min(max(cursor_row - scroll_top, 0), max(height - 1, 0))

    {visible_lines, cursor_x, visible_cursor_y}
  end

  defp wrap_lines(content, %{value: "", placeholder: placeholder}, width)
       when is_binary(placeholder) and placeholder != "" do
    {lines, _cursor_row, _cursor_x} = do_wrap_lines(content, 0, width)
    {lines, 0, 0}
  end

  defp wrap_lines(content, state, width) do
    do_wrap_lines(content, state.cursor, width)
  end

  defp do_wrap_lines(content, cursor, width) do
    width = max(width, 1)
    indexed_graphemes = Enum.with_index(String.graphemes(content))

    {lines, current_line, column, cursor_row, cursor_x} =
      wrap_graphemes(indexed_graphemes, cursor, width, [], [], 0, nil, nil)

    {lines, cursor_row, cursor_x} =
      if cursor == String.length(content) do
        if column >= width and current_line != "" do
          {lines ++ [current_line, ""], length(lines) + 1, 0}
        else
          {lines ++ [current_line], length(lines), column}
        end
      else
        {lines ++ [current_line], cursor_row, cursor_x}
      end

    {lines, cursor_row, cursor_x}
  end

  defp wrap_graphemes([], _cursor, _width, lines, current_items, column, cursor_row, cursor_x) do
    {lines, items_to_string(current_items), column, cursor_row || 0, cursor_x || 0}
  end

  defp wrap_graphemes(
         [{grapheme, grapheme_index} | rest],
         cursor,
         width,
         lines,
         current_items,
         column,
         cursor_row,
         cursor_x
       ) do
    {cursor_row, cursor_x} =
      if grapheme_index == cursor do
        {length(lines), column}
      else
        {cursor_row, cursor_x}
      end

    grapheme_width = grapheme_width(grapheme)

    cond do
      grapheme == "\n" ->
        wrap_graphemes(
          rest,
          cursor,
          width,
          lines ++ [items_to_string(current_items)],
          [],
          0,
          cursor_row,
          cursor_x
        )

      column == 0 or column + grapheme_width <= width ->
        wrap_graphemes(
          rest,
          cursor,
          width,
          lines,
          current_items ++ [{grapheme, grapheme_width}],
          column + grapheme_width,
          cursor_row,
          cursor_x
        )

      true ->
        case split_at_last_whitespace(current_items) do
          nil ->
            wrap_graphemes(
              [{grapheme, grapheme_index} | rest],
              cursor,
              width,
              lines ++ [items_to_string(current_items)],
              [],
              0,
              cursor_row,
              cursor_x
            )

          {line_items, carry_items} ->
            wrap_graphemes(
              [{grapheme, grapheme_index} | rest],
              cursor,
              width,
              lines ++ [items_to_string(line_items)],
              carry_items,
              items_width(carry_items),
              cursor_row,
              cursor_x
            )
        end
    end
  end

  defp split_at_last_whitespace(items) do
    case Enum.find_index(Enum.reverse(items), fn {grapheme, _width} -> whitespace?(grapheme) end) do
      nil ->
        nil

      reverse_index ->
        split_index = length(items) - reverse_index
        Enum.split(items, split_index)
    end
  end

  defp items_to_string(items) do
    items
    |> Enum.map_join("", fn {grapheme, _width} -> grapheme end)
  end

  defp items_width(items) do
    Enum.reduce(items, 0, fn {_grapheme, width}, total -> total + width end)
  end

  defp scroll_top(_cursor_row, height, line_count) when line_count <= height do
    0
  end

  defp scroll_top(cursor_row, height, _line_count) do
    max(cursor_row - height + 1, 0)
  end

  defp resolve_layout(%Breeze.Viewport{} = layout, box) do
    resolve_layout(Map.from_struct(layout), box)
  end

  defp resolve_layout(layout, box) when is_map(layout) do
    initial_width = initial_viewport_width(box)
    initial_height = initial_viewport_height(box)

    layout
    |> Map.update(:viewport_width, initial_width, &max(&1 || 0, initial_width || 0))
    |> Map.update(:viewport_height, initial_height, &max(&1 || 0, initial_height || 0))
    |> Breeze.Viewport.from_dimensions()
  end

  defp initial_layout(box) do
    width = initial_viewport_width(box)
    height = initial_viewport_height(box)

    if is_integer(width) and width > 0 and is_integer(height) and height > 0 do
      Breeze.Viewport.from_dimensions(%{width: width, height: height, left: 0, top: 0})
    else
      nil
    end
  end

  defp initial_viewport_width(%{width: width}) when is_integer(width) and width > 0, do: width

  defp initial_viewport_width(%{style: %{width: width}}) when is_integer(width) and width > 0,
    do: width

  defp initial_viewport_width(_box), do: nil

  defp initial_viewport_height(%{height: height}) when is_integer(height) and height > 0,
    do: height

  defp initial_viewport_height(%{style: %{height: height}})
       when is_integer(height) and height > 0,
       do: height

  defp initial_viewport_height(_box), do: nil

  defp cursor_char(content, row, display_cursor) when is_binary(content) do
    content
    |> String.split("\n", trim: false)
    |> Enum.at(row, "")
    |> grapheme_at_display_column(display_cursor)
    |> Kernel.||(" ")
  end

  defp grapheme_at_display_column(content, display_column)
       when is_binary(content) and display_column >= 0 do
    {grapheme, _column} =
      Enum.reduce_while(String.graphemes(content), {nil, 0}, fn grapheme, {_found, column} ->
        width = grapheme_width(grapheme)

        cond do
          column == display_column -> {:halt, {grapheme, column}}
          column > display_column -> {:halt, {nil, column}}
          true -> {:cont, {nil, column + width}}
        end
      end)

    grapheme
  end

  defp grapheme_at_display_column(_content, _display_column), do: nil

  defp grapheme_width(grapheme) when is_binary(grapheme) do
    grapheme
    |> Ucwidth.width()
    |> max(0)
  end

  defp whitespace?(grapheme) when is_binary(grapheme) do
    String.match?(grapheme, ~r/\s/u)
  end

  defp border_left_offset(%{style: %{border: border}}), do: if(border.left, do: 1, else: 0)
  defp border_right_offset(%{style: %{border: border}}), do: if(border.right, do: 1, else: 0)
  defp border_top_offset(%{style: %{border: border}}), do: if(border.top, do: 1, else: 0)
  defp border_bottom_offset(%{style: %{border: border}}), do: if(border.bottom, do: 1, else: 0)

  defp content_viewport_width(width, %{style: style}) when is_integer(width) do
    max(
      width -
        border_left_offset(%{style: style}) -
        border_right_offset(%{style: style}) -
        style_value(style, :padding_left) -
        style_value(style, :padding_right),
      0
    )
  end

  defp content_viewport_width(width, _box), do: max(width || 1, 1)

  defp content_viewport_height(height, %{style: style} = box) when is_integer(height) do
    max(
      height -
        border_top_offset(box) -
        border_bottom_offset(box) -
        style_value(style, :padding_top) -
        style_value(style, :padding_bottom),
      1
    )
  end

  defp content_viewport_height(height, _box), do: max(height || 1, 1)

  defp content_left_offset(%{style: style} = box) do
    border_left_offset(box) + style_value(style, :padding_left)
  end

  defp content_top_offset(%{style: style} = box) do
    border_top_offset(box) + style_value(style, :padding_top)
  end

  defp style_value(style, side_key) do
    case Map.get(style, side_key) do
      value when is_integer(value) -> value
      _ -> Map.get(style, :padding, 0) || 0
    end
  end
end
