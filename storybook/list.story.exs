defmodule Breeze.Storybook.Stories.Blocks.ListStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "list",
      title: "List",
      description: "Keyboard-selectable list with a muted unfocused state.",
      notes: [
        "Uses the built-in list implicit.",
        "The preview starts with the list unfocused so the muted rows are visible.",
        "Focus the list to restore the active selected-row highlight."
      ],
      source: "<.list id=\"languages\" variant=\"muted\" class=\"width-full\">...</.list>"
    }
  end

  def render(_story) do
    assigns = %{languages: ~w(Elixir Erlang Gleam Rust Go Zig Lua Haskell)}

    ~H"""
    <.list
      id="storybook-list"
      variant="muted"
      list-selected="elixir"
      class="width-full height-8 bg-panel focus:border-primary"
    >
      <:item :for={language <- @languages} value={String.downcase(language)}>{language}</:item>
    </.list>
    """
  end
end
