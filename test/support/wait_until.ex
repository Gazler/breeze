defmodule Breeze.TestSupport.WaitUntil do
  @moduledoc false

  def wait_until(fun, attempts \\ 20)

  def wait_until(fun, attempts) when attempts > 0 do
    case fun.() do
      true ->
        :ok

      false ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)

      other ->
        other
    end
  end

  def wait_until(_fun, 0), do: ExUnit.Assertions.flunk("condition not met")
end
