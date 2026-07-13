defmodule Breeze.Storybook.RegistryTest do
  use ExUnit.Case, async: true

  alias Breeze.Storybook.Registry

  @block_story_ids %{
    button: "button",
    dropdown: "dropdown",
    flash_group: "flash",
    input: "input",
    keybinding_bar: "keybinding-bar",
    list: "list",
    markdown: "markdown",
    modal: "modal",
    panel: "panel",
    scroll: "scroll",
    table: "table",
    tabs: "tabs",
    textarea: "textarea",
    tree: "tree"
  }

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

  test "every public Breeze block has an associated story" do
    assert MapSet.new(Map.keys(@block_story_ids)) ==
             MapSet.new(Breeze.Blocks.__breeze_components__())

    story_ids = Registry.stories() |> Enum.map(& &1.id) |> MapSet.new()

    assert @block_story_ids
           |> Map.values()
           |> Enum.all?(&MapSet.member?(story_ids, &1))
  end
end
