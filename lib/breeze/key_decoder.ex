defmodule Breeze.KeyDecoder do
  @moduledoc false

  def decode("\e"), do: "Escape"
  def decode("\r"), do: "Enter"
  def decode("\b"), do: %{"ctrlKey" => true, "key" => "Backspace"}
  def decode("\x17"), do: %{"ctrlKey" => true, "key" => "w"}

  def decode(raw_key) do
    cond do
      match?({:ctrl, _key}, decode_ctrl_char(raw_key)) ->
        case decode_ctrl_char(raw_key) do
          {:ctrl, key} -> %{"ctrlKey" => true, "key" => key}
        end

      String.starts_with?(raw_key, "\eO") ->
        raw_key
        |> String.trim_leading("\eO")
        |> convert_ss3()

      String.starts_with?(raw_key, Termite.Screen.escape_code()) ->
        raw_key
        |> String.trim_leading(Termite.Screen.escape_code())
        |> convert_csi()

      true ->
        raw_key
    end
  end

  defp convert_ss3("P"), do: "F1"
  defp convert_ss3("Q"), do: "F2"
  defp convert_ss3("R"), do: "F3"
  defp convert_ss3("S"), do: "F4"
  defp convert_ss3(key), do: key

  defp convert_csi("[A"), do: "F1"
  defp convert_csi("[B"), do: "F2"
  defp convert_csi("[C"), do: "F3"
  defp convert_csi("[D"), do: "F4"
  defp convert_csi("11~"), do: "F1"
  defp convert_csi("12~"), do: "F2"
  defp convert_csi("13~"), do: "F3"
  defp convert_csi("14~"), do: "F4"
  defp convert_csi("A"), do: "ArrowUp"
  defp convert_csi("B"), do: "ArrowDown"
  defp convert_csi("C"), do: "ArrowRight"
  defp convert_csi("D"), do: "ArrowLeft"
  defp convert_csi("Z"), do: "ShiftTab"
  defp convert_csi("H"), do: "Home"
  defp convert_csi("F"), do: "End"
  defp convert_csi("1~"), do: "Home"
  defp convert_csi("3~"), do: "Delete"
  defp convert_csi("4~"), do: "End"
  defp convert_csi("5~"), do: "PageUp"
  defp convert_csi("6~"), do: "PageDown"
  defp convert_csi("8;5u"), do: %{"ctrlKey" => true, "key" => "Backspace"}
  defp convert_csi("127;5u"), do: %{"ctrlKey" => true, "key" => "w"}

  defp convert_csi(sequence) do
    case decode_modified_csi(sequence) do
      nil -> sequence
      event -> event
    end
  end

  defp decode_modified_csi(sequence) do
    case Regex.run(~r/^1;(\d+)([ABCDHF])$/, sequence) do
      [_, modifier, suffix] ->
        suffix
        |> modified_cursor_key()
        |> with_modifiers(String.to_integer(modifier))

      _ ->
        case Regex.run(~r/^(\d+);(\d+)u$/, sequence) do
          [_, codepoint, modifier] ->
            decode_csi_u_key(String.to_integer(codepoint))
            |> with_modifiers(String.to_integer(modifier))

          _ ->
            case Regex.run(~r/^27;(\d+);(\d+)~$/, sequence) do
              [_, modifier, codepoint] ->
                decode_csi_u_key(String.to_integer(codepoint))
                |> with_modifiers(String.to_integer(modifier))

              _ ->
                nil
            end
        end
    end
  end

  defp modified_cursor_key("A"), do: "ArrowUp"
  defp modified_cursor_key("B"), do: "ArrowDown"
  defp modified_cursor_key("C"), do: "ArrowRight"
  defp modified_cursor_key("D"), do: "ArrowLeft"
  defp modified_cursor_key("H"), do: "Home"
  defp modified_cursor_key("F"), do: "End"

  defp decode_csi_u_key(13), do: "Enter"

  defp decode_csi_u_key(codepoint) when codepoint in 32..0x10FFFF do
    codepoint |> List.wrap() |> List.to_string()
  end

  defp decode_csi_u_key(_), do: nil

  defp with_modifiers(nil, _modifier), do: nil

  defp with_modifiers(key, modifier) when is_binary(key) and is_integer(modifier) do
    flags =
      modifier
      |> Kernel.-(1)
      |> modifier_flags()

    if flags == %{} do
      key
    else
      Map.put(flags, "key", key)
    end
  end

  defp modifier_flags(bits) do
    %{}
    |> maybe_put_modifier("shiftKey", Bitwise.band(bits, 1) != 0)
    |> maybe_put_modifier("altKey", Bitwise.band(bits, 2) != 0)
    |> maybe_put_modifier("ctrlKey", Bitwise.band(bits, 4) != 0)
  end

  defp maybe_put_modifier(event, _key, false), do: event
  defp maybe_put_modifier(event, key, true), do: Map.put(event, key, true)

  defp decode_ctrl_char(<<codepoint::utf8>>)
       when codepoint in 1..26 and codepoint not in [8, 9, 13] do
    key =
      codepoint
      |> Kernel.+(96)
      |> List.wrap()
      |> List.to_string()

    {:ctrl, key}
  end

  defp decode_ctrl_char(_raw_key), do: nil
end
