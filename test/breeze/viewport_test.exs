defmodule Breeze.ViewportTest do
  use ExUnit.Case, async: true

  alias Breeze.Viewport

  describe "from_dimensions/1" do
    test "normalizes a dimension map" do
      viewport =
        Viewport.from_dimensions(%{
          left: 3,
          top: 4,
          height: 10,
          viewport_height: 4,
          content_height: 20
        })

      assert viewport.left == 3
      assert viewport.top == 4
      assert viewport.height == 10
      assert viewport.viewport_height == 4
      assert viewport.content_height == 20
    end

    test "falls back to sane defaults" do
      viewport = Viewport.from_dimensions(nil)

      assert viewport.left == 0
      assert viewport.top == 0
      assert viewport.height == 0
      assert viewport.viewport_height == 0
      assert viewport.content_height == 0
    end
  end

  describe "scroll helpers" do
    test "clamps y scroll offset" do
      viewport = Viewport.from_dimensions(%{viewport_height: 5, content_height: 12, height: 5})

      assert Viewport.max_scroll_y(viewport) == 7
      assert Viewport.clamp_scroll_y(-3, viewport) == 0
      assert Viewport.clamp_scroll_y(2, viewport) == 2
      assert Viewport.clamp_scroll_y(99, viewport) == 7
    end

    test "keeps range visible with padding" do
      viewport = Viewport.from_dimensions(%{viewport_height: 4, content_height: 20, height: 4})

      assert Viewport.ensure_range_visible(0, 0, 0, viewport, padding: 1) == 0
      assert Viewport.ensure_range_visible(0, 7, 7, viewport, padding: 1) == 5
      assert Viewport.ensure_range_visible(6, 3, 3, viewport, padding: 1) == 2
    end
  end
end
