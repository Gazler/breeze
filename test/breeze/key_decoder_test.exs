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
    assert Breeze.KeyDecoder.decode("\t") == "\t"
    assert Breeze.KeyDecoder.decode("\e") == "Escape"
    assert Breeze.KeyDecoder.decode("\r") == "Enter"
  end

  test "normalizes common ctrl-backspace sequences to word-delete" do
    assert Breeze.KeyDecoder.decode("\e[8;5u") == "\x17"
    assert Breeze.KeyDecoder.decode("\e[127;5u") == "\x17"
  end

  test "decodes ctrl-j and ctrl-k CSI-u sequences as structured key events" do
    assert Breeze.KeyDecoder.decode("\e[106;5u") == %{"ctrlKey" => true, "key" => "j"}
    assert Breeze.KeyDecoder.decode("\e[107;5u") == %{"ctrlKey" => true, "key" => "k"}
  end

  test "keeps raw ctrl-h for input word-delete compatibility and decodes raw ctrl-l" do
    assert Breeze.KeyDecoder.decode("\b") == "\b"
    assert Breeze.KeyDecoder.decode("\f") == %{"ctrlKey" => true, "key" => "l"}
  end

  test "decodes modified cursor CSI sequences as structured key events" do
    assert Breeze.KeyDecoder.decode("\e[1;5D") == %{"ctrlKey" => true, "key" => "ArrowLeft"}
    assert Breeze.KeyDecoder.decode("\e[1;5C") == %{"ctrlKey" => true, "key" => "ArrowRight"}
  end
end
