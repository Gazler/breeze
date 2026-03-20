defmodule Breeze.BlocksTest do
  use ExUnit.Case, async: true

  alias Breeze.Blocks

  describe "merge_class/2" do
    test "matches merge_style semantics" do
      assert Blocks.merge_class("border width-24 height-8", "width-32 bg-4") ==
               "border width-32 height-8 bg-4"
    end
  end

  describe "merge_style/2" do
    test "nil override returns default unchanged" do
      assert Blocks.merge_style("border width-24", nil) == "border width-24"
    end

    test "empty string override returns default unchanged" do
      assert Blocks.merge_style("border width-24", "") == "border width-24"
    end

    test "override replaces a numeric-suffixed token" do
      assert Blocks.merge_style("border width-24 height-8", "width-32") ==
               "border width-32 height-8"
    end

    test "override replaces a non-numeric-suffixed token" do
      assert Blocks.merge_style("border overflow-scroll", "overflow-hidden") ==
               "border overflow-hidden"
    end

    test "new token from override is appended" do
      assert Blocks.merge_style("border width-24", "bg-4") == "border width-24 bg-4"
    end

    test "state-prefixed tokens are matched by their full prefix" do
      assert Blocks.merge_style("border focus:border-3", "focus:border-2") ==
               "border focus:border-2"
    end

    test "multiple overrides are applied in one call" do
      assert Blocks.merge_style(
               "border width-24 height-8 overflow-scroll focus:border-3",
               "width-32 focus:border-2"
             ) ==
               "border width-32 height-8 overflow-scroll focus:border-2"
    end
  end
end
