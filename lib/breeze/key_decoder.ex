defmodule Breeze.KeyDecoder do
  @moduledoc false

  def decode("\e"), do: "Escape"
  def decode("\r"), do: "Enter"

  def decode(raw_key) do
    cond do
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
  defp convert_csi(key), do: key
end
