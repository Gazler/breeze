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

  test "decodes common ctrl-backspace sequences as structured key events" do
    assert Breeze.KeyDecoder.decode("\e[8;5u") == %{"ctrlKey" => true, "key" => "Backspace"}
    assert Breeze.KeyDecoder.decode("\e[127;5u") == %{"ctrlKey" => true, "key" => "w"}
  end

  test "decodes ctrl-j and ctrl-k CSI-u sequences as structured key events" do
    assert Breeze.KeyDecoder.decode("\e[106;5u") == %{"ctrlKey" => true, "key" => "j"}
    assert Breeze.KeyDecoder.decode("\e[107;5u") == %{"ctrlKey" => true, "key" => "k"}
  end

  test "decodes shift-enter CSI-u sequence as a structured key event" do
    assert Breeze.KeyDecoder.decode("\e[13;2u") == %{"shiftKey" => true, "key" => "Enter"}
  end

  test "decodes xterm modifyOtherKeys enter sequence as a structured key event" do
    assert Breeze.KeyDecoder.decode("\e[27;2;13~") == %{"shiftKey" => true, "key" => "Enter"}
  end

  test "decodes raw ctrl-h and ctrl-l as structured key events" do
    assert Breeze.KeyDecoder.decode("\b") == %{"ctrlKey" => true, "key" => "Backspace"}
    assert Breeze.KeyDecoder.decode("\f") == %{"ctrlKey" => true, "key" => "l"}
  end

  test "decodes modified cursor CSI sequences as structured key events" do
    assert Breeze.KeyDecoder.decode("\e[1;5D") == %{"ctrlKey" => true, "key" => "ArrowLeft"}
    assert Breeze.KeyDecoder.decode("\e[1;5C") == %{"ctrlKey" => true, "key" => "ArrowRight"}
  end
end
