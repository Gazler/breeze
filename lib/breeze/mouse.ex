defmodule Breeze.Mouse do
  @moduledoc false

  import Bitwise

  @type button :: String.t()
  @type action :: String.t()
  @type event :: %{
          required(String.t()) => button() | action() | non_neg_integer() | boolean()
        }

  @spec decode(binary()) :: {:ok, event()} | :error
  def decode("\e[<" <> rest) do
    with [raw_code, raw_x, raw_tail] <- String.split(rest, ";", parts: 3),
         {code, ""} <- Integer.parse(raw_code),
         {x, ""} when x > 0 <- Integer.parse(raw_x),
         tail_size when tail_size > 0 <- byte_size(raw_tail),
         raw_y_size = tail_size - 1,
         <<raw_y::binary-size(^raw_y_size), suffix>> <- raw_tail,
         {y, ""} when y > 0 <- Integer.parse(raw_y),
         true <- suffix in [?M, ?m] do
      event = %{
        "button" => button(code),
        "action" => action(code, suffix),
        "x" => x - 1,
        "y" => y - 1
      }

      {:ok, Map.merge(event, modifier_flags(code))}
    else
      _ -> :error
    end
  end

  def decode(_), do: :error

  defp button(code) do
    cond do
      (code &&& 64) != 0 -> wheel_button(code)
      (code &&& 3) == 3 -> "release"
      (code &&& 3) == 0 -> "left"
      (code &&& 3) == 1 -> "middle"
      true -> "right"
    end
  end

  defp modifier_flags(code) do
    %{}
    |> maybe_put_modifier("shiftKey", (code &&& 4) != 0)
    |> maybe_put_modifier("altKey", (code &&& 8) != 0)
    |> maybe_put_modifier("ctrlKey", (code &&& 16) != 0)
  end

  defp maybe_put_modifier(event, _key, false), do: event
  defp maybe_put_modifier(event, key, true), do: Map.put(event, key, true)

  defp action(code, suffix) do
    cond do
      (code &&& 32) != 0 -> "move"
      suffix == ?m -> "release"
      true -> "press"
    end
  end

  defp wheel_button(code) do
    case code &&& 3 do
      0 -> "wheel_up"
      1 -> "wheel_down"
      _ -> "release"
    end
  end
end
