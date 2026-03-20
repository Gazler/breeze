defmodule Breeze.KeyDecoderTest do
  use ExUnit.Case, async: true

  test "decodes common F1 variants" do
    assert Breeze.KeyDecoder.decode("\eOP") == "F1"
    assert Breeze.KeyDecoder.decode("\e[11~") == "F1"
    assert Breeze.KeyDecoder.decode("\e[[A") == "F1"
  end

  test "decodes common navigation keys" do
    assert Breeze.KeyDecoder.decode("\e[A") == "ArrowUp"
    assert Breeze.KeyDecoder.decode("\e[B") == "ArrowDown"
    assert Breeze.KeyDecoder.decode("\e[3~") == "Delete"
    assert Breeze.KeyDecoder.decode("\e[Z") == "ShiftTab"
    assert Breeze.KeyDecoder.decode("\e") == "Escape"
    assert Breeze.KeyDecoder.decode("\r") == "Enter"
  end

  test "normalizes common ctrl-backspace sequences to word-delete" do
    assert Breeze.KeyDecoder.decode("\e[8;5u") == "\x17"
    assert Breeze.KeyDecoder.decode("\e[127;5u") == "\x17"
  end
end
