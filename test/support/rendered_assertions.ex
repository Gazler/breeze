defmodule Breeze.TestSupport.RenderedAssertions do
  @moduledoc false

  @doc """
  Asserts rendered text equality or containment, ignoring CRLF versus LF endings.

      assert_rendered box.content == expected
      assert_rendered box.content =~ expected

  Other whitespace and terminal escape sequences remain significant.
  """
  defmacro assert_rendered({operator, _, [actual, expected]}) when operator in [:==, :=~] do
    quote do
      require ExUnit.Assertions

      actual = String.replace(unquote(actual), "\r\n", "\n")
      expected = String.replace(unquote(expected), "\r\n", "\n")

      ExUnit.Assertions.assert(unquote(operator)(actual, expected))
    end
  end
end
