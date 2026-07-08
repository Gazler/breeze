defmodule Breeze.KeyDecoderTest do
  use ExUnit.Case, async: true

  test "decodes common F1 variants" do
    assert Breeze.KeyDecoder.decode("\eOP") == "F1"
    assert Breeze.KeyDecoder.decode("\e[11~") == "F1"
    assert Breeze.KeyDecoder.decode("\e[[A") == "F1"
  end

  test "decodes enhanced keyboard F3 and F4 variants" do
    assert Breeze.KeyDecoder.decode("\e[13~") == "F3"
    assert Breeze.KeyDecoder.decode("\e[13;1~") == "F3"
    assert Breeze.KeyDecoder.decode("\e[13;1:1~") == "F3"
    assert Breeze.KeyDecoder.decode("\e[1R") == "F3"
    assert Breeze.KeyDecoder.decode("\e[1;2R") == %{"shiftKey" => true, "key" => "F3"}

    assert Breeze.KeyDecoder.decode("\e[S") == "F4"
    assert Breeze.KeyDecoder.decode("\e[1S") == "F4"
    assert Breeze.KeyDecoder.decode("\e[14;1~") == "F4"
    assert Breeze.KeyDecoder.decode("\e[14;1:1~") == "F4"
    assert Breeze.KeyDecoder.decode("\e[1;2S") == %{"shiftKey" => true, "key" => "F4"}
  end

  test "decodes tilde function keys without modifiers" do
    assert Breeze.KeyDecoder.decode("\e[21~") == "F10"
    assert Breeze.KeyDecoder.decode("\e[21;1~") == "F10"
  end

  test "decodes kitty private-use function keys" do
    assert Breeze.KeyDecoder.decode("\e[57376u") == "F13"
    assert Breeze.KeyDecoder.decode("\e[57376;2u") == %{"shiftKey" => true, "key" => "F13"}
  end

  test "decodes common navigation keys" do
    assert Breeze.KeyDecoder.decode("\e[A") == "ArrowUp"
    assert Breeze.KeyDecoder.decode("\e[B") == "ArrowDown"
    assert Breeze.KeyDecoder.decode("\e[3~") == "Delete"
    assert Breeze.KeyDecoder.decode("\e[Z") == "ShiftTab"
    assert Breeze.KeyDecoder.decode("\e[1;2Z") == "ShiftTab"
    assert Breeze.KeyDecoder.decode("\e[9u") == "\t"
    assert Breeze.KeyDecoder.decode("\e[9;1u") == "\t"
    assert Breeze.KeyDecoder.decode("\e[9;2u") == "ShiftTab"
    assert Breeze.KeyDecoder.decode("\e[9;2:1u") == "ShiftTab"
    assert Breeze.KeyDecoder.decode("\e[27;2;9~") == "ShiftTab"
    assert Breeze.KeyDecoder.decode("\e[27;2;9u") == "ShiftTab"
    assert Breeze.KeyDecoder.decode("\t") == "\t"
    assert Breeze.KeyDecoder.decode("\e") == "Escape"
    assert Breeze.KeyDecoder.decode("\e[27u") == "Escape"
    assert Breeze.KeyDecoder.decode("\e[27;1u") == "Escape"
    assert Breeze.KeyDecoder.decode("\r") == "Enter"
  end

  test "decodes common ctrl-backspace sequences as structured key events" do
    for sequence <- [
          "\b",
          "\e[8;5u",
          "\e[127;5u",
          "\e[27;5;8u",
          "\e[27;5;127u",
          "\e[27;5;127~",
          "\e[127;5~"
        ] do
      assert Breeze.KeyDecoder.decode(sequence) == %{"ctrlKey" => true, "key" => "Backspace"}
    end
  end

  test "decodes ctrl-j and ctrl-k CSI-u sequences as structured key events" do
    assert Breeze.KeyDecoder.decode("\e[106;5u") == %{"ctrlKey" => true, "key" => "j"}
    assert Breeze.KeyDecoder.decode("\e[107;5u") == %{"ctrlKey" => true, "key" => "k"}
  end

  test "decodes ctrl-c variants as structured key events" do
    assert Breeze.KeyDecoder.decode("\x03") == %{"ctrlKey" => true, "key" => "c"}
    assert Breeze.KeyDecoder.decode("\e[99;5u") == %{"ctrlKey" => true, "key" => "c"}
    assert Breeze.KeyDecoder.decode("\e[27;5;99u") == %{"ctrlKey" => true, "key" => "c"}
    assert Breeze.KeyDecoder.decode("\e[27;5;99~") == %{"ctrlKey" => true, "key" => "c"}
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
