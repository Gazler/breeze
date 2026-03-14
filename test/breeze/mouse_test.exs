defmodule Breeze.MouseTest do
  use ExUnit.Case, async: true

  alias Breeze.Mouse

  test "decodes sgr left click press" do
    assert Mouse.decode("\e[<0;12;7M") ==
             {:ok, %{button: :left, action: :press, x: 12, y: 7, modifiers: []}}
  end

  test "decodes sgr release" do
    assert Mouse.decode("\e[<0;12;7m") ==
             {:ok, %{button: :left, action: :release, x: 12, y: 7, modifiers: []}}
  end

  test "decodes sgr motion with modifiers" do
    assert Mouse.decode("\e[<36;5;3M") ==
             {:ok, %{button: :left, action: :move, x: 5, y: 3, modifiers: [:shift]}}
  end

  test "decodes sgr wheel scroll" do
    assert Mouse.decode("\e[<65;20;4M") ==
             {:ok, %{button: :wheel_down, action: :press, x: 20, y: 4, modifiers: []}}
  end

  test "rejects non mouse input" do
    assert Mouse.decode("\e[A") == :error
  end
end
