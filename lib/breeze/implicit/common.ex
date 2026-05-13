defmodule Breeze.Implicit.Common do
  @moduledoc false

  def normalize_selected_index(_index, []), do: nil

  def normalize_selected_index(index, values) when is_integer(index) do
    index
    |> max(0)
    |> min(length(values) - 1)
  end

  def normalize_selected_index(_index, _values), do: nil

  def selected_value(_values, nil), do: nil
  def selected_value(values, index), do: Enum.at(values, index)

  def next_index(%{selected_index: nil}, delta) when delta >= 0, do: 0
  def next_index(%{selected_index: nil, values: values}, _delta), do: max(length(values) - 1, 0)

  def next_index(%{selected_index: selected_index, values: values, loop: loop?}, delta) do
    max_index = max(length(values) - 1, 0)
    next = selected_index + delta

    cond do
      loop? && next > max_index -> 0
      loop? && next < 0 -> max_index
      true -> next
    end
  end

  def change_reply(state) do
    {{:change, %{value: state.selected, index: state.selected_index, offset: state.offset}},
     state}
  end

  def selected_modifier(flags, state) do
    case Keyword.get(flags, :value) do
      value when not is_nil(value) and state.selected == value -> [selected: true]
      _ -> []
    end
  end

  def root_scroll_modifier(state), do: [scroll_y: state.offset]

  def wheel_repeat(%{repeat: repeat}) when is_integer(repeat) and repeat > 0, do: repeat
  def wheel_repeat(_mouse), do: 1

  def bool_option(attrs, key, default, opts \\ []) do
    numeric? = Keyword.get(opts, :numeric, false)

    case Map.get(attrs, key) do
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      "1" when numeric? -> true
      "0" when numeric? -> false
      nil -> default
      _ -> default
    end
  end

  def int_option(attrs, key, default, opts \\ []) do
    clamp? = Keyword.get(opts, :clamp, true)

    attrs
    |> Map.get(key)
    |> normalize_int(default, clamp?)
  end

  def normalize_int(value, default \\ 0)
  def normalize_int(value, _default) when is_integer(value), do: max(value, 0)

  def normalize_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> max(value, 0)
      _ -> normalize_default_int(default, true)
    end
  end

  def normalize_int(_value, default), do: normalize_default_int(default, true)

  defp normalize_int(value, default, clamp?)
  defp normalize_int(nil, default, clamp?), do: normalize_default_int(default, clamp?)

  defp normalize_int(value, _default, true) when is_integer(value), do: max(value, 0)
  defp normalize_int(value, _default, false) when is_integer(value), do: value

  defp normalize_int(value, default, clamp?) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} when clamp? -> max(value, 0)
      {value, ""} -> value
      _ -> normalize_default_int(default, clamp?)
    end
  end

  defp normalize_int(_value, default, clamp?), do: normalize_default_int(default, clamp?)

  defp normalize_default_int(value, clamp?)
  defp normalize_default_int(nil, _clamp?), do: nil
  defp normalize_default_int(value, true) when is_integer(value), do: max(value, 0)
  defp normalize_default_int(value, false) when is_integer(value), do: value
  defp normalize_default_int(_value, _clamp?), do: 0
end
