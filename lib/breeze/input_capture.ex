defmodule Breeze.InputCapture do
  @moduledoc false

  @modifier_keys ["ctrlKey", "altKey", "metaKey"]

  def captures_key?(meta, key) when is_map(meta) do
    cond do
      Map.get(meta, :captures_keys) == true -> true
      captures_listed_key?(meta, key) -> true
      captures_printable_key?(meta, key) -> true
      captures_text_editing_key?(meta, key) -> true
      captures_control_key?(meta, key) -> true
      captures_focus_key?(meta, key) -> true
      :otherwise -> false
    end
  end

  def captures_key?(_meta, _key), do: false

  def captures_listed_key?(meta, key) when is_map(meta) do
    case Map.get(meta, :captures_keys) do
      keys when is_list(keys) -> key_name(key) in keys
      _ -> false
    end
  end

  def captures_listed_key?(_meta, _key), do: false

  def captures_printable_key?(%{captures_printable_keys: true}, key), do: printable_key?(key)

  def captures_printable_key?(_meta, _key), do: false

  def captures_text_editing_key?(%{captures_printable_keys: true}, key),
    do: text_editing_key?(key)

  def captures_text_editing_key?(_meta, _key), do: false

  def printable_key?(%{"__batched_printable__" => true, "key" => key}) when is_binary(key) do
    printable_text?(key)
  end

  def printable_key?(%{"key" => key} = event) when is_binary(key) do
    if modified_input?(event), do: false, else: printable_key?(key)
  end

  def printable_key?(<<_codepoint::utf8>> = key), do: printable_text?(key)
  def printable_key?(key) when is_binary(key), do: false

  def printable_key?(_key), do: false

  def captures_control_key?(%{captures_control_keys: true}, key), do: control_key?(key)

  def captures_control_key?(_meta, _key), do: false

  def control_key?(%{"ctrlKey" => value}) when value in [true, "true"], do: true
  def control_key?(%{"key" => key}), do: control_key?(key)

  def control_key?(<<codepoint>>) when codepoint in [?\b, ?\t, ?\r], do: false
  def control_key?(<<codepoint>>) when codepoint in 1..26, do: true
  def control_key?(key) when is_binary(key), do: false

  def control_key?(_key), do: false

  def captures_focus_key?(%{captures_focus_keys: true}, key), do: focus_key?(key)

  def captures_focus_key?(_meta, _key), do: false

  def focus_key?(%{"key" => key}) when key in ["\t", "Tab", "ShiftTab"], do: true
  def focus_key?(key), do: normalize_focus_key(key) in ["\t", "ShiftTab"]

  def normalize_focus_key(%{"key" => key} = event) when key in ["\t", "Tab"] do
    if truthy?(Map.get(event, "shiftKey")) do
      "ShiftTab"
    else
      "\t"
    end
  end

  def normalize_focus_key(%{"key" => "ShiftTab"}), do: "ShiftTab"

  def normalize_focus_key(key), do: key

  defp key_name(%{"key" => key}), do: key
  defp key_name(key), do: key

  defp text_editing_key?(%{"ctrlKey" => value, "key" => "Backspace"})
       when value in [true, "true"],
       do: true

  defp text_editing_key?(%{"ctrlKey" => value, "key" => "w"}) when value in [true, "true"],
    do: true

  defp text_editing_key?(key) when key in ["\x08", "\x17"], do: true
  defp text_editing_key?(_key), do: false

  defp printable_text?(key), do: Breeze.Printable.text?(key)

  defp modified_input?(event) do
    Enum.any?(@modifier_keys, fn key ->
      event
      |> Map.get(key)
      |> truthy?()
    end)
  end

  defp truthy?(value), do: value in [true, "true"]
end
