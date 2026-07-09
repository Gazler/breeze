defmodule Breeze.Input do
  @moduledoc false

  def decode(raw_key) do
    case Breeze.Mouse.decode(raw_key) do
      {:ok, event} ->
        {:mouse, event}

      :error ->
        {:key, decode_key(raw_key)}
    end
  end

  defp decode_key(raw_key) when is_binary(raw_key) do
    if printable_text?(raw_key) and String.length(raw_key) > 1 do
      %{"key" => raw_key, "__batched_printable__" => true}
    else
      Breeze.KeyDecoder.decode(raw_key)
    end
  end

  defp decode_key(raw_key), do: Breeze.KeyDecoder.decode(raw_key)

  defp printable_text?(raw_key), do: Breeze.Printable.text?(raw_key)
end
