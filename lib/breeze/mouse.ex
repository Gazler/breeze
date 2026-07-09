defmodule Breeze.Mouse do
  @moduledoc false

  import Bitwise

  @type event :: %{
          button: :left | :middle | :right | :release | :wheel_up | :wheel_down,
          action: :press | :release | :move,
          x: pos_integer(),
          y: pos_integer(),
          modifiers: [:shift | :alt | :ctrl]
        }

  @spec decode(binary()) :: {:ok, event()} | :error
  def decode("\e[<" <> rest) do
    with [raw_code, raw_x, raw_tail] <- String.split(rest, ";", parts: 3),
         {code, ""} <- Integer.parse(raw_code),
         {x, ""} <- Integer.parse(raw_x),
         tail_size when tail_size > 0 <- byte_size(raw_tail),
         raw_y_size = tail_size - 1,
         <<raw_y::binary-size(^raw_y_size), suffix>> <- raw_tail,
         {y, ""} <- Integer.parse(raw_y),
         true <- suffix in [?M, ?m] do
      {:ok,
       %{
         button: button(code),
         action: action(code, suffix),
         x: x,
         y: y,
         modifiers: modifiers(code)
       }}
    else
      _ -> :error
    end
  end

  def decode(_), do: :error

  defp button(code) do
    cond do
      (code &&& 64) != 0 -> wheel_button(code)
      (code &&& 3) == 3 -> :release
      (code &&& 3) == 0 -> :left
      (code &&& 3) == 1 -> :middle
      true -> :right
    end
  end

  defp modifiers(code) do
    []
    |> maybe_add_modifier(code, 4, :shift)
    |> maybe_add_modifier(code, 8, :alt)
    |> maybe_add_modifier(code, 16, :ctrl)
  end

  defp maybe_add_modifier(modifiers, code, mask, modifier) do
    if (code &&& mask) != 0 do
      modifiers ++ [modifier]
    else
      modifiers
    end
  end

  defp action(code, suffix) do
    cond do
      (code &&& 32) != 0 -> :move
      suffix == ?m -> :release
      true -> :press
    end
  end

  defp wheel_button(code) do
    case code &&& 3 do
      0 -> :wheel_up
      1 -> :wheel_down
      _ -> :release
    end
  end
end
