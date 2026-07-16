defmodule Breeze.MouseTest do
  use ExUnit.Case, async: true

  alias Breeze.Mouse

  test "decodes sgr left click press" do
    assert Mouse.decode("\e[<0;12;7M") ==
             {:ok,
              %{
                "button" => "left",
                "action" => "press",
                "x" => 11,
                "y" => 6
              }}
  end

  test "decodes sgr release" do
    assert Mouse.decode("\e[<0;12;7m") ==
             {:ok,
              %{
                "button" => "left",
                "action" => "release",
                "x" => 11,
                "y" => 6
              }}
  end

  test "decodes sgr motion with modifiers" do
    assert Mouse.decode("\e[<60;5;3M") ==
             {:ok,
              %{
                "button" => "left",
                "action" => "move",
                "x" => 4,
                "y" => 2,
                "shiftKey" => true,
                "altKey" => true,
                "ctrlKey" => true
              }}
  end

  test "decodes sgr wheel scroll" do
    assert Mouse.decode("\e[<65;20;4M") ==
             {:ok,
              %{
                "button" => "wheel_down",
                "action" => "press",
                "x" => 19,
                "y" => 3
              }}
  end

  test "normalizes the top-left sgr position to zero" do
    assert {:ok, %{"x" => 0, "y" => 0}} = Mouse.decode("\e[<0;1;1M")
  end

  test "rejects non-positive sgr coordinates" do
    assert Mouse.decode("\e[<0;0;1M") == :error
    assert Mouse.decode("\e[<0;1;0M") == :error
  end

  test "rejects non mouse input" do
    assert Mouse.decode("\e[A") == :error
  end
end
