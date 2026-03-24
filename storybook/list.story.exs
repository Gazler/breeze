defmodule Breeze.Storybook.Stories.Blocks.ListStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "list",
      title: "List",
      description: "Keyboard-selectable list with highlighted rows.",
      notes: [
        "Uses the built-in list implicit.",
        "A future version could wire live selection details in the docs pane."
      ],
      source: "<.list id=\"languages\">...</.list>"
    }
  end

  def render(_story) do
    assigns = %{languages: ~w(Elixir Erlang Gleam Rust Go Zig Lua Haskell)}

    ~H"""
    <.list id="storybook-list" class="width-24 height-8 bg-panel focus:border-primary">
      <:item :for={language <- @languages} value={String.downcase(language)}>{language}</:item>
    </.list>
    """
  end
end
