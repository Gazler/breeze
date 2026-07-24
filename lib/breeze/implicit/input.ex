defmodule Breeze.Implicit.Input do
  @moduledoc false

  @behaviour Breeze.Implicit

  alias BackBreeze.Ucwidth
  alias Breeze.Implicit.TextEditor
  alias Breeze.Theme

  def init(_items, root_attrs, last_state) do
    value = Map.get(root_attrs, :"input-value", "")
    cursor = TextEditor.initial_cursor(value, Map.get(root_attrs, :"input-cursor"), last_state)

    attrs_state = %{
      value: value,
      cursor: cursor,
      placeholder: Map.get(root_attrs, :"input-placeholder")
    }

    state = Map.merge(last_state, attrs_state)
    state = TextEditor.normalize_state(state)

    {:ok, state,
     rerender_every: 500,
     active_when_focused: true,
     captures_printable_keys: true,
     batch_printable_keys: true,
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

  def handle_event(_, %{"key" => "ArrowLeft"}, %{cursor: cursor} = state) when cursor > 0 do
    TextEditor.move_left(state)
  end

  def handle_event(_, %{"key" => "ArrowRight"}, state) do
    TextEditor.move_right(state)
  end

  def handle_event(_, %{"key" => "Home"}, state),
    do: TextEditor.move_to_start(state)

  def handle_event(_, %{"key" => "End"}, state) do
    TextEditor.move_to_end(state)
  end

  def handle_event(_, %{"key" => key} = event, state) do
    TextEditor.insert_key(key, event, state)
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
    layout = resolve_layout(layout, state)
    source = source_content(box.content, state)
    {content, display_cursor} = render_visible_content(source, state, layout, box)
    theme = Map.get(ctx, :theme)
    defaults = Theme.default_style(theme)

    overlay = %{
      x: layout.left + content_left_offset(box) + display_cursor,
      y: layout.top + content_top_offset(box),
      char: cursor_char(content, display_cursor),
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
        source = source_content(box.content, state)
        {content, display_cursor} = render_visible_content(source, state, layout, box)
        theme = Map.get(ctx, :theme)
        defaults = Theme.default_style(theme)

        overlay = %{
          x: content_left_offset(box) + display_cursor,
          y: content_top_offset(box),
          char: cursor_char(content, display_cursor),
          foreground_color: Map.get(defaults, :background_color),
          background_color: Theme.color(theme, :cursor) || Theme.color(theme, :accent),
          visible?: Breeze.TerminalOverlay.visible?(now, last_interaction_at)
        }

        {:ok, %{box | content: content}, overlays: [overlay]}
    end
  end

  def animate(:root, box, _flags, _state, _ctx), do: box

  def animate(:child, box, _flags, _state, _ctx), do: box

  defp display_cursor_index(content, %{value: value, cursor: cursor}) when is_binary(content) do
    clamped_cursor = min(max(cursor, 0), String.length(value))

    prefix_display_width(content, value) +
      display_width(take_graphemes(value, clamped_cursor)) +
      max(cursor - clamped_cursor, 0)
  end

  defp cursor_char(content, display_cursor) when is_binary(content) do
    grapheme_at_display_column(content, display_cursor) || " "
  end

  defp source_content(_content, %{value: "", placeholder: placeholder})
       when is_binary(placeholder) and placeholder != "" do
    placeholder
  end

  defp source_content(content, %{value: value}) when is_binary(content) and is_binary(value) do
    if value == "" or String.contains?(content, value) do
      content
    else
      value
    end
  end

  defp placeholder_modifiers(%{value: "", placeholder: placeholder})
       when is_binary(placeholder) and placeholder != "" do
    [placeholder: true]
  end

  defp placeholder_modifiers(_state), do: []

  defp render_visible_content(content, state, %{viewport_width: width}, box)
       when is_binary(content) and is_integer(width) and width > 0 do
    width = content_viewport_width(width, box)
    display_cursor = display_cursor_index(content, state)
    content_width = display_width(content)
    scrolled? = display_cursor >= width and width > 1
    visible_width = visible_width(scrolled?, width)
    scroll_left = scroll_left(display_cursor, visible_width, content_width)

    {visible_content, actual_scroll_left} =
      slice_display_columns(content, scroll_left, visible_width)

    visible_cursor = visible_cursor_index(display_cursor, actual_scroll_left, width, scrolled?)

    {visible_content, visible_cursor}
  end

  defp render_visible_content(content, state, _layout, _box) when is_binary(content) do
    {content, display_cursor_index(content, state)}
  end

  defp resolve_layout(%Breeze.Viewport{} = layout, _state), do: layout

  defp resolve_layout(layout, state) when is_map(layout) do
    layout
    |> Map.put_new(:viewport_width, Map.get(state, :viewport_width))
    |> Breeze.Viewport.from_dimensions()
  end

  defp initial_layout(%{width: width}) when is_integer(width) and width > 0 do
    Breeze.Viewport.from_dimensions(%{width: width, height: 1, left: 0, top: 0})
  end

  defp initial_layout(%{style: %{width: width}}) when is_integer(width) and width > 0 do
    Breeze.Viewport.from_dimensions(%{width: width, height: 1, left: 0, top: 0})
  end

  defp initial_layout(_box), do: nil

  defp visible_width(true, width) when width > 1 do
    width - 1
  end

  defp visible_width(_scrolled?, width), do: width

  defp scroll_left(display_cursor, width, content_length)
       when display_cursor >= content_length and content_length >= width do
    max(content_length - width, 0)
  end

  defp scroll_left(display_cursor, width, _content_length) when display_cursor >= width do
    display_cursor - (width - 1)
  end

  defp scroll_left(_display_cursor, _width, _content_length), do: 0

  defp visible_cursor_index(_display_cursor, _scroll_left, width, true) do
    max(width - 1, 0)
  end

  defp visible_cursor_index(display_cursor, scroll_left, width, false) do
    min(max(display_cursor - scroll_left, 0), max(width - 1, 0))
  end

  defp prefix_display_width(content, value) when is_binary(content) and is_binary(value) do
    cond do
      value == "" and String.starts_with?(content, " ") ->
        1

      value == "" ->
        0

      true ->
        case String.split(content, value, parts: 2) do
          [prefix, _suffix] -> display_width(prefix)
          _ -> 0
        end
    end
  end

  defp slice_display_columns(content, start, visible_width) do
    {_column, graphemes, actual_start, _used_width} =
      Enum.reduce_while(String.graphemes(content), {0, [], nil, 0}, fn grapheme,
                                                                       {column, acc, actual_start,
                                                                        used_width} ->
        grapheme_width = grapheme_width(grapheme)
        next_column = column + grapheme_width

        cond do
          next_column <= start ->
            {:cont, {next_column, acc, actual_start, used_width}}

          column < start ->
            clipped_width = next_column - start

            if clipped_width <= visible_width do
              {:cont,
               {next_column, [String.duplicate(" ", clipped_width) | acc], start,
                used_width + clipped_width}}
            else
              {:halt, {column, acc, actual_start, used_width}}
            end

          used_width + grapheme_width <= visible_width ->
            {:cont,
             {next_column, [grapheme | acc], actual_start || column, used_width + grapheme_width}}

          used_width < visible_width ->
            trailing_width = visible_width - used_width

            {:halt,
             {column, [String.duplicate(" ", trailing_width) | acc], actual_start || column,
              visible_width}}

          true ->
            {:halt, {column, acc, actual_start, used_width}}
        end
      end)

    {graphemes |> Enum.reverse() |> Enum.join(), actual_start || start}
  end

  defp take_graphemes(value, count) when is_binary(value) and is_integer(count) and count > 0 do
    value
    |> String.graphemes()
    |> Enum.take(count)
    |> Enum.join()
  end

  defp take_graphemes(_value, _count), do: ""

  defp display_width(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reduce(0, fn grapheme, total -> total + grapheme_width(grapheme) end)
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

  defp border_left_offset(%{style: %{border: border}}), do: if(border.left, do: 1, else: 0)
  defp border_top_offset(%{style: %{border: border}}), do: if(border.top, do: 1, else: 0)

  defp content_viewport_width(width, %{style: style}) when is_integer(width) do
    max(width - style_value(style, :padding_left) - style_value(style, :padding_right), 0)
  end

  defp content_viewport_width(width, _box), do: width

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
