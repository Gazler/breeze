defmodule Breeze.Storybook.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Breeze.Storybook.Discovery
  alias Breeze.Storybook.Registry

  test "discovers public Breeze.Blocks component exports" do
    components = Discovery.components()

    assert Enum.any?(components, &(&1.id == "input"))
    assert Enum.any?(components, &(&1.id == "tabs"))
    refute Enum.any?(components, &(&1.id == "merge_class"))
  end

  test "registry stories are normalized and addressable by id" do
    stories = Registry.stories()

    assert Enum.any?(stories, &(&1.id == "input"))
    assert %{id: "tabs"} = Registry.story("tabs")
  end

  test "registry can load a single story file" do
    stories = Registry.stories("storybook", file: "dropdown.story.exs")

    assert Enum.map(stories, & &1.id) == ["dropdown"]
    assert %{id: "dropdown"} = Registry.first_story("storybook", file: "dropdown.story.exs")
  end

  test "flash story covers each flash_group variant" do
    [%{id: "flash", variants: variants}] = Registry.stories("storybook", file: "flash.story.exs")

    assert Enum.map(variants, & &1.id) == ["default", "square", "rounded"]
  end
end
