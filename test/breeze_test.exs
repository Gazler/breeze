defmodule BreezeTest do
  use ExUnit.Case
  doctest Breeze

  test "greets the world" do
    assert Breeze.hello() == :world
  end
end
