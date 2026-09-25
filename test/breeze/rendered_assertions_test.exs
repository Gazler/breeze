defmodule Breeze.RenderedAssertionsTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.RenderedAssertions

  test "normalizes both operands for equality and containment" do
    assert_rendered "one\r\ntwo\nthree" == "one\ntwo\r\nthree"
    assert_rendered "one\r\ntwo\nthree" =~ "one\ntwo\r\n"
  end

  test "preserves significant differences and assertion diagnostics" do
    for {actual, expected} <- [{" OK ", "OK"}, {"\e[1mOK", "OK"}, {"a\rb", "a\nb"}] do
      error = assert_raise ExUnit.AssertionError, fn -> assert_rendered(actual == expected) end
      assert error.left == actual
      assert error.right == expected
    end

    assert_raise ExUnit.AssertionError, fn -> assert_rendered("OK\r\n" =~ "missing") end
  end

  test "evaluates each operand once" do
    assert_rendered(
      (send(self(), :actual) && "OK\r\n") ==
        (send(self(), :expected) && "OK\n")
    )

    assert_receive :actual
    assert_receive :expected
    assert Process.info(self(), :messages) == {:messages, []}
  end
end
