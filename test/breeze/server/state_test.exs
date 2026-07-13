defmodule Breeze.Server.StateTest do
  use ExUnit.Case, async: true

  test "server state remains a flat map" do
    assert map_size(%Breeze.Server{}) <= 32
  end
end
