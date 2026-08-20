defmodule Breeze.Theme.ContrastTest do
  use ExUnit.Case, async: true

  alias Breeze.Theme.Contrast

  test "calculates WCAG contrast for RGB and hexadecimal colors" do
    assert_in_delta Contrast.ratio("#000000", "#ffffff"), 21.0, 0.001
    assert_in_delta Contrast.ratio({119, 119, 119}, {255, 255, 255}), 4.478, 0.001
    assert Contrast.ratio(0, 7) == nil
    assert Contrast.ratio("#invalid", "#ffffff") == nil
  end

  test "adjusts lightness in either direction while retaining color character" do
    cases = [
      {{220, 50, 47}, [{0, 43, 54}, {18, 58, 67}]},
      {{221, 221, 221}, [{240, 240, 240}, {225, 225, 225}]}
    ]

    for {source, backgrounds} <- cases do
      adjusted = Contrast.adjust(source, backgrounds, 4.5)

      for background <- backgrounds do
        assert Contrast.ratio(adjusted, background) >= 4.5
      end

      assert color_spread(adjusted) >= color_spread(source) * 0.85
    end
  end

  defp color_spread(color) do
    channels = Tuple.to_list(color)
    Enum.max(channels) - Enum.min(channels)
  end
end
