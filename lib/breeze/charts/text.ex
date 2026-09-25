defmodule Breeze.Charts.Text do
  @moduledoc false

  def truncate(text, width) do
    {graphemes, _remaining} =
      text
      |> String.graphemes()
      |> Enum.reduce_while({[], width}, fn grapheme, {graphemes, remaining} ->
        size = BackBreeze.Utils.string_length(grapheme)

        if size <= remaining do
          {:cont, {[grapheme | graphemes], remaining - size}}
        else
          {:halt, {graphemes, remaining}}
        end
      end)

    graphemes |> Enum.reverse() |> IO.iodata_to_binary()
  end
end
