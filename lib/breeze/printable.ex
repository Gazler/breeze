defmodule Breeze.Printable do
  @moduledoc false

  @non_text_keys ["\n", "\r", "\t", "\v", "\f"]

  def text?(""), do: false

  def text?(value) when is_binary(value) do
    String.printable?(value) and Enum.all?(String.graphemes(value), &grapheme?/1)
  end

  def text?(_value), do: false

  def single_key?(value) when is_binary(value) do
    String.length(value) == 1 and text?(value)
  end

  def single_key?(_value), do: false

  def grapheme?(grapheme) when is_binary(grapheme) do
    grapheme not in @non_text_keys and not control_grapheme?(grapheme)
  end

  def grapheme?(_grapheme), do: false

  defp control_grapheme?(grapheme) do
    grapheme
    |> String.to_charlist()
    |> Enum.any?(&control_codepoint?/1)
  end

  defp control_codepoint?(codepoint), do: codepoint in 0..31 or codepoint == 127
end
