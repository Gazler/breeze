defmodule Breeze.InputRouter.StateTest do
  use ExUnit.Case, async: true

  test "input router state remains a flat map" do
    assert map_size(%Breeze.InputRouter{}) <= 32
  end
end
