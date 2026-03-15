defmodule Breeze.Input do
  @moduledoc false

  def decode(raw_key) do
    case Breeze.Mouse.decode(raw_key) do
      {:ok, event} -> {:mouse, event}
      :error -> {:key, Breeze.KeyDecoder.decode(raw_key)}
    end
  end
end
