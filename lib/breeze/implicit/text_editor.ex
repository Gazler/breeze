defmodule Breeze.Implicit.TextEditor do
  @moduledoc false

  def max_cursor(value), do: String.length(value)

  def normalize_state(%{value: value, cursor: cursor} = state) do
    %{state | cursor: clamp_cursor(cursor, value)}
  end

  def backspace(%{cursor: 0} = state), do: {:noreply, state}

  def backspace(%{cursor: cursor} = state) when cursor > 0 do
    {before, rest} = split_value(state.value, cursor)
    value = drop_trailing_grapheme(before) <> rest

    change(
      state
      |> Map.merge(%{value: value, cursor: cursor - 1})
      |> reset_preferred_column()
      |> normalize_state()
    )
  end

  def delete_previous_word(%{cursor: cursor} = state) when cursor > 0 do
    {before, rest} = split_value(state.value, cursor)

    kept_before =
      before
      |> trim_trailing_whitespace()
      |> drop_previous_word()
      |> trim_trailing_whitespace()

    value = kept_before <> rest

    change(
      state
      |> Map.merge(%{value: value, cursor: String.length(kept_before)})
      |> reset_preferred_column()
      |> normalize_state()
    )
  end

  def delete_previous_word(state), do: {:noreply, state}

  def delete_forward(state) do
    {before, rest} = split_value(state.value, state.cursor)

    if rest != "" do
      change(
        state
        |> Map.put(:value, before <> drop_leading_grapheme(rest))
        |> reset_preferred_column()
        |> normalize_state()
      )
    else
      {:noreply, state}
    end
  end

  def insert_newline(state) do
    {before, rest} = split_value(state.value, state.cursor)
    value = before <> "\n" <> rest

    change(
      state
      |> Map.merge(%{value: value, cursor: state.cursor + 1})
      |> reset_preferred_column()
      |> normalize_state()
    )
  end

  def submit(state) do
    {{:submit, %{value: state.value, cursor: state.cursor}}, state}
  end

  def move_left(%{cursor: cursor} = state) when cursor > 0 do
    change(state |> Map.put(:cursor, cursor - 1) |> reset_preferred_column() |> normalize_state())
  end

  def move_left(state), do: {:noreply, state}

  def move_right(state) do
    if state.cursor < max_cursor(state.value) do
      change(
        state
        |> Map.put(:cursor, state.cursor + 1)
        |> reset_preferred_column()
        |> normalize_state()
      )
    else
      {:noreply, state}
    end
  end

  def move_to_start(%{cursor: 0} = state), do: {:noreply, state}

  def move_to_start(state) do
    change(state |> Map.put(:cursor, 0) |> reset_preferred_column() |> normalize_state())
  end

  def move_to_end(state) do
    end_cursor = max_cursor(state.value)

    if state.cursor == end_cursor do
      {:noreply, state}
    else
      change(
        state
        |> Map.put(:cursor, end_cursor)
        |> reset_preferred_column()
        |> normalize_state()
      )
    end
  end

  def move_line_start(state) do
    line_start = current_line_start(state.value, state.cursor)

    if state.cursor == line_start do
      {:noreply, state}
    else
      change(
        state
        |> Map.put(:cursor, line_start)
        |> reset_preferred_column()
        |> normalize_state()
      )
    end
  end

  def move_line_end(state) do
    line_end = current_line_end(state.value, state.cursor)

    if state.cursor == line_end do
      {:noreply, state}
    else
      change(state |> Map.put(:cursor, line_end) |> reset_preferred_column() |> normalize_state())
    end
  end

  def move_vertical(state, direction) when direction in [-1, 1] do
    lines = String.split(state.value, "\n", trim: false)
    {line_index, line_offset} = cursor_line_position(lines, state.cursor)
    target_index = line_index + direction

    cond do
      target_index < 0 or target_index >= length(lines) ->
        {:noreply, state}

      true ->
        preferred_column = Map.get(state, :preferred_column) || line_offset
        cursor = cursor_for_line(lines, target_index, preferred_column)

        change(
          state
          |> Map.merge(%{cursor: cursor, preferred_column: preferred_column})
          |> normalize_state()
        )
    end
  end

  def insert_key(key, event, state, opts \\ []) do
    if insertable_key?(key, event, opts) do
      {before, rest} = split_value(state.value, state.cursor)
      value = before <> key <> rest

      change(
        state
        |> Map.merge(%{value: value, cursor: state.cursor + String.length(key)})
        |> reset_preferred_column()
        |> normalize_state()
      )
    else
      {:noreply, state}
    end
  end

  defp change(state) do
    {{:change, %{value: state.value, cursor: state.cursor}}, state}
  end

  defp reset_preferred_column(state) do
    if Map.has_key?(state, :preferred_column),
      do: Map.put(state, :preferred_column, nil),
      else: state
  end

  defp clamp_cursor(cursor, value) when is_integer(cursor) do
    cursor
    |> max(0)
    |> min(max_cursor(value))
  end

  defp clamp_cursor(_cursor, value), do: max_cursor(value)

  defp split_value(value, cursor) do
    String.split_at(value, clamp_cursor(cursor, value))
  end

  defp drop_trailing_grapheme(""), do: ""

  defp drop_trailing_grapheme(value) do
    value
    |> String.graphemes()
    |> Enum.drop(-1)
    |> Enum.join()
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

  defp current_line_start(value, cursor) do
    {before, _rest} = split_value(value, cursor)

    case String.split(before, "\n") do
      [] -> 0
      segments -> String.length(before) - String.length(List.last(segments))
    end
  end

  defp current_line_end(value, cursor) do
    {_before, rest} = split_value(value, cursor)

    case String.split(rest, "\n", parts: 2) do
      [segment, _] -> cursor + String.length(segment)
      [segment] -> cursor + String.length(segment)
      _ -> cursor
    end
  end

  defp cursor_line_position(lines, cursor) do
    Enum.reduce_while(Enum.with_index(lines), {0, cursor}, fn {line, index},
                                                              {_line_index, offset} ->
      line_length = String.length(line)

      cond do
        offset <= line_length ->
          {:halt, {index, offset}}

        true ->
          {:cont, {index + 1, max(offset - line_length - 1, 0)}}
      end
    end)
  end

  defp cursor_for_line(lines, target_index, preferred_column) do
    before_length =
      lines
      |> Enum.take(target_index)
      |> Enum.reduce(0, fn line, total -> total + String.length(line) + 1 end)

    target_line =
      lines
      |> Enum.at(target_index, "")

    before_length + min(preferred_column, String.length(target_line))
  end

  defp insertable_key?(key, %{"__batched_printable__" => true}, opts) when is_binary(key) do
    forbidden =
      if Keyword.get(opts, :allow_newline, false),
        do: ["\r", "\t", "\v", "\f"],
        else: ["\n", "\r", "\t", "\v", "\f"]

    key != "" and
      String.printable?(key) and
      Enum.all?(String.graphemes(key), fn grapheme ->
        not control_character?(grapheme) and grapheme not in forbidden
      end)
  end

  defp insertable_key?(key, _event, opts) when is_binary(key) do
    forbidden =
      if Keyword.get(opts, :allow_newline, false),
        do: ["\r", "\t", "\v", "\f"],
        else: ["\n", "\r", "\t", "\v", "\f"]

    String.length(key) == 1 and
      not control_character?(key) and
      String.printable?(key) and
      key not in forbidden
  end

  defp insertable_key?(_key, _event, _opts), do: false

  defp control_character?(<<"\n">>), do: false
  defp control_character?(<<codepoint::utf8>>) when codepoint < 32, do: true
  defp control_character?(<<"\x7f">>), do: true
  defp control_character?(_key), do: false
end
