defmodule Breeze.InputCaptureTest do
  use ExUnit.Case, async: true

  alias Breeze.InputCapture

  test "captures explicitly listed keys" do
    meta = %{captures_keys: ["PageUp", "PageDown"]}

    assert InputCapture.captures_key?(meta, %{"key" => "PageUp"})
    assert InputCapture.captures_key?(meta, "PageDown")
    refute InputCapture.captures_key?(meta, %{"key" => "F10"})
    refute InputCapture.captures_key?(meta, "ArrowDown")
  end

  test "captures printable keys when enabled" do
    meta = %{captures_printable_keys: true}

    assert InputCapture.captures_key?(meta, %{"key" => "a"})
    assert InputCapture.captures_key?(meta, "é")
    assert InputCapture.captures_key?(meta, %{"__batched_printable__" => true, "key" => "abc"})
    assert InputCapture.captures_key?(meta, %{"key" => "Backspace", "ctrlKey" => true})
    assert InputCapture.captures_key?(meta, %{"key" => "w", "ctrlKey" => true})
    assert InputCapture.captures_key?(meta, "\x08")
    assert InputCapture.captures_key?(meta, "\x17")
    refute InputCapture.captures_key?(meta, %{"key" => "a", "ctrlKey" => true})
    refute InputCapture.captures_key?(meta, "\t")
  end

  test "captures control keys when enabled" do
    meta = %{captures_control_keys: true}

    assert InputCapture.captures_key?(meta, %{"key" => "c", "ctrlKey" => true})
    assert InputCapture.captures_key?(meta, <<3>>)
    refute InputCapture.captures_key?(meta, "\t")
  end

  test "captures focus keys when enabled" do
    meta = %{captures_focus_keys: true}

    assert InputCapture.captures_key?(meta, %{"key" => "Tab"})
    assert InputCapture.captures_key?(meta, %{"key" => "Tab", "shiftKey" => true})
    assert InputCapture.captures_key?(meta, "ShiftTab")
    refute InputCapture.captures_key?(meta, "ArrowDown")
  end
end
