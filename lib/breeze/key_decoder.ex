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

  defp convert_csi("P"), do: "F1"
  defp convert_csi("Q"), do: "F2"
  defp convert_csi("R"), do: "F3"
  defp convert_csi("S"), do: "F4"
  defp convert_csi("1P"), do: "F1"
  defp convert_csi("1Q"), do: "F2"
  defp convert_csi("1R"), do: "F3"
  defp convert_csi("1S"), do: "F4"
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
    [
      &decode_modified_cursor_csi/1,
      &decode_xterm_modify_other_keys_csi_u/1,
      &decode_csi_u_with_modifiers/1,
      &decode_csi_u/1,
      &decode_tilde_csi/1,
      &decode_xterm_modify_other_keys_tilde/1
    ]
    |> Enum.find_value(& &1.(sequence))
  end

  defp decode_modified_cursor_csi(sequence) do
    with [_, modifier, suffix] <- Regex.run(~r/^1;(\d+)([ABCDHFPQRSZ])$/, sequence) do
      suffix
      |> modified_cursor_key()
      |> with_modifiers(to_int(modifier))
    end
  end

  defp decode_xterm_modify_other_keys_csi_u(sequence) do
    with [_, modifier, codepoint] <- Regex.run(~r/^27;(\d+);(\d+)u$/, sequence) do
      codepoint
      |> to_int()
      |> decode_csi_u_key()
      |> with_modifiers(to_int(modifier))
    end
  end

  defp decode_csi_u_with_modifiers(sequence) do
    with [_, codepoint, modifier] <- Regex.run(~r/^(\d+);(\d+)(?::[0-9:]+)?u$/, sequence) do
      codepoint
      |> to_int()
      |> decode_csi_u_key()
      |> with_modifiers(to_int(modifier))
    end
  end

  defp decode_csi_u(sequence) do
    with [_, codepoint] <- Regex.run(~r/^(\d+)u$/, sequence) do
      codepoint
      |> to_int()
      |> decode_csi_u_key()
    end
  end

  defp decode_tilde_csi(sequence) do
    case Regex.run(~r/^(\d+)(?:;(\d+)(?::\d+)?)?~$/, sequence) do
      [_, codepoint] ->
        codepoint
        |> to_int()
        |> decode_tilde_key()

      [_, codepoint, modifier] ->
        codepoint
        |> to_int()
        |> decode_tilde_key()
        |> maybe_with_modifiers(modifier)

      _ ->
        nil
    end
  end

  defp decode_xterm_modify_other_keys_tilde(sequence) do
    with [_, modifier, codepoint] <- Regex.run(~r/^27;(\d+);(\d+)~$/, sequence) do
      codepoint
      |> to_int()
      |> decode_csi_u_key()
      |> with_modifiers(to_int(modifier))
    end
  end

  defp maybe_with_modifiers(key, ""), do: key
  defp maybe_with_modifiers(key, nil), do: key
  defp maybe_with_modifiers(key, modifier), do: with_modifiers(key, to_int(modifier))

  defp to_int(value), do: String.to_integer(value)

  defp modified_cursor_key("A"), do: "ArrowUp"
  defp modified_cursor_key("B"), do: "ArrowDown"
  defp modified_cursor_key("C"), do: "ArrowRight"
  defp modified_cursor_key("D"), do: "ArrowLeft"
  defp modified_cursor_key("H"), do: "Home"
  defp modified_cursor_key("F"), do: "End"
  defp modified_cursor_key("P"), do: "F1"
  defp modified_cursor_key("Q"), do: "F2"
  defp modified_cursor_key("R"), do: "F3"
  defp modified_cursor_key("S"), do: "F4"
  defp modified_cursor_key("Z"), do: "\t"

  defp decode_tilde_key(1), do: "Home"
  defp decode_tilde_key(2), do: "Insert"
  defp decode_tilde_key(3), do: "Delete"
  defp decode_tilde_key(4), do: "End"
  defp decode_tilde_key(5), do: "PageUp"
  defp decode_tilde_key(6), do: "PageDown"
  defp decode_tilde_key(7), do: "Home"
  defp decode_tilde_key(8), do: "End"
  defp decode_tilde_key(11), do: "F1"
  defp decode_tilde_key(12), do: "F2"
  defp decode_tilde_key(13), do: "F3"
  defp decode_tilde_key(14), do: "F4"
  defp decode_tilde_key(15), do: "F5"
  defp decode_tilde_key(17), do: "F6"
  defp decode_tilde_key(18), do: "F7"
  defp decode_tilde_key(19), do: "F8"
  defp decode_tilde_key(20), do: "F9"
  defp decode_tilde_key(21), do: "F10"
  defp decode_tilde_key(23), do: "F11"
  defp decode_tilde_key(24), do: "F12"
  defp decode_tilde_key(_codepoint), do: nil

  defp decode_csi_u_key(9), do: "\t"
  defp decode_csi_u_key(13), do: "Enter"
  defp decode_csi_u_key(codepoint) when codepoint in 57376..57398, do: "F#{codepoint - 57363}"

  defp decode_csi_u_key(codepoint) when codepoint in 32..0x10FFFF do
    codepoint |> List.wrap() |> List.to_string()
  end

  defp decode_csi_u_key(_), do: nil

  defp with_modifiers(nil, _modifier), do: nil

  defp with_modifiers("\t", modifier) when is_integer(modifier) do
    if modifier |> Kernel.-(1) |> Bitwise.band(1) != 0 do
      "ShiftTab"
    else
      "\t"
    end
  end

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
