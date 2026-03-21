defmodule Breeze.Implicit.Input do
  @moduledoc false

  alias Breeze.Theme

  @type state :: %{
          value: String.t(),
          cursor: non_neg_integer(),
          placeholder: String.t() | nil
        }

  def init(items, last_state), do: init(items, %{}, last_state)

  def init(_items, root_attrs, last_state) do
    value = Map.get(root_attrs, :"input-value", "")

    cursor =
      case Map.fetch(root_attrs, :"input-cursor") do
        {:ok, raw_cursor} ->
          if is_binary(raw_cursor), do: String.to_integer(raw_cursor), else: raw_cursor

        :error ->
          if Map.get(last_state, :value) == value and is_integer(Map.get(last_state, :cursor)) do
            Map.get(last_state, :cursor)
          else
            max_cursor(value)
          end
      end

    attrs_state = %{
      value: value,
      cursor: cursor,
      placeholder: Map.get(root_attrs, :"input-placeholder")
    }

    state = Map.merge(last_state, attrs_state)
    state = normalize_state(state)

    {:ok, state, rerender_every: 500, active_when_focused: true}
  end

  @spec handle_event(term(), map(), state()) :: {:noreply, state()} | {{:change, map()}, state()}
  def handle_event(_, %{"key" => "\x7f"}, %{cursor: 0} = state), do: {:noreply, state}

  def handle_event(_, %{"key" => "\x7f"}, %{cursor: cursor} = state) when cursor > 0 do
    {before, rest} = split_value(state.value, cursor)
    value = drop_trailing_grapheme(before) <> rest
    change(%{state | value: value, cursor: cursor - 1} |> normalize_state())
  end

  def handle_event(_, %{"key" => key}, %{cursor: cursor} = state)
      when key in ["\x08", "\x17"] and cursor > 0 do
    {before, rest} = split_value(state.value, cursor)

    kept_before =
      before
      |> trim_trailing_whitespace()
      |> drop_previous_word()
      |> trim_trailing_whitespace()

    value = kept_before <> rest
    change(%{state | value: value, cursor: String.length(kept_before)} |> normalize_state())
  end

  def handle_event(_, %{"key" => key}, state) when key in ["\x08", "\x17"], do: {:noreply, state}

  def handle_event(_, %{"key" => "Delete"}, state) do
    {before, rest} = split_value(state.value, state.cursor)

    if rest != "" do
      change(%{state | value: before <> drop_leading_grapheme(rest)} |> normalize_state())
    else
      {:noreply, state}
    end
  end

  def handle_event(_, %{"key" => "ArrowLeft"}, %{cursor: cursor} = state) when cursor > 0 do
    change(%{state | cursor: cursor - 1} |> normalize_state())
  end

  def handle_event(_, %{"key" => "ArrowRight"}, state) do
    if state.cursor < max_cursor(state.value) do
      change(%{state | cursor: state.cursor + 1} |> normalize_state())
    else
      {:noreply, state}
    end
  end

  def handle_event(_, %{"key" => "Home"}, %{cursor: 0} = state), do: {:noreply, state}

  def handle_event(_, %{"key" => "Home"}, state),
    do: change(%{state | cursor: 0} |> normalize_state())

  def handle_event(_, %{"key" => "End"}, state) do
    end_cursor = max_cursor(state.value)

    if state.cursor == end_cursor,
      do: {:noreply, state},
      else: change(%{state | cursor: end_cursor} |> normalize_state())
  end

  def handle_event(_, %{"key" => key}, state) do
    if insertable_key?(key) do
      {before, rest} = split_value(state.value, state.cursor)
      value = before <> key <> rest
      change(%{state | value: value, cursor: state.cursor + 1} |> normalize_state())
    else
      {:noreply, state}
    end
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

  def animate(:root, box, _flags, _state, _ctx), do: box

  def animate(:child, box, _flags, _state, _ctx), do: box

  defp change(state) do
    {{:change, %{value: state.value, cursor: state.cursor}}, state}
  end

  defp normalize_state(%{value: value, cursor: cursor} = state) do
    %{state | cursor: clamp_cursor(cursor, value)}
  end

  defp clamp_cursor(cursor, value) when is_integer(cursor) do
    cursor
    |> max(0)
    |> min(max_cursor(value))
  end

  defp clamp_cursor(_cursor, value), do: max_cursor(value)

  defp max_cursor(value), do: String.length(value)

  defp split_value(value, cursor) do
    String.split_at(value, clamp_cursor(cursor, value))
  end

  defp drop_trailing_grapheme(""), do: ""

  defp drop_trailing_grapheme(value) do
    graphemes = String.graphemes(value)
    graphemes |> Enum.drop(-1) |> Enum.join()
  end

  defp drop_leading_grapheme(""), do: ""

  defp drop_leading_grapheme(value) do
    value
    |> String.graphemes()
    |> tl()
    |> Enum.join()
  end

  defp trim_trailing_whitespace(value) do
    Regex.replace(~r/\s+$/u, value, "")
  end

  defp drop_previous_word(value) do
    Regex.replace(~r/\S+$/u, value, "")
  end

  defp display_cursor_index(content, %{value: value, cursor: cursor}) when is_binary(content) do
    prefix_len(content, value) + cursor
  end

  defp cursor_char(content, display_cursor) when is_binary(content) do
    String.at(content, display_cursor) || " "
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
    content_length = String.length(content)
    scrolled? = display_cursor >= width and width > 1
    visible_width = visible_width(scrolled?, width)
    scroll_left = scroll_left(display_cursor, visible_width, content_length)
    visible_cursor = visible_cursor_index(display_cursor, scroll_left, width, scrolled?)

    {slice_graphemes(content, scroll_left, visible_width), visible_cursor}
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

  defp prefix_len(content, value) when is_binary(content) and is_binary(value) do
    cond do
      value == "" and String.starts_with?(content, " ") ->
        1

      value == "" ->
        0

      true ->
        case String.split(content, value, parts: 2) do
          [prefix, _suffix] -> String.length(prefix)
          _ -> 0
        end
    end
  end

  defp slice_graphemes(content, start, visible_width) do
    content
    |> String.graphemes()
    |> Enum.slice(start, visible_width)
    |> Enum.join()
  end

  defp insertable_key?(key) when is_binary(key) do
    String.length(key) == 1 and
      not control_character?(key) and
      String.printable?(key) and
      key not in ["\n", "\r", "\t", "\v", "\f"]
  end

  defp insertable_key?(_key), do: false

  defp control_character?(<<codepoint::utf8>>) when codepoint < 32, do: true
  defp control_character?(<<"\x7f">>), do: true
  defp control_character?(_key), do: false

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
