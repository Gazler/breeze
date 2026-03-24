defmodule Breeze.Storybook.Stories.Blocks.ListStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "list",
      title: "List",
      description: "Keyboard-selectable list with a muted unfocused state.",
      variants: [
        %{
          id: "muted",
          label: "Muted",
          source: "<.list id=\"languages\" variant=\"muted\" class=\"width-full height-8\">...</.list>",
          notes: [
            "Uses the built-in list implicit.",
            "The preview starts with the list unfocused so the muted rows are visible.",
            "Focus the list to restore the active selected-row highlight."
          ]
        },
        %{
          id: "accent",
          label: "Accent",
          description: "Keyboard-selectable list with an accent-selected state.",
          source: "<.list id=\"languages\" variant=\"accent\" class=\"width-full height-8\">...</.list>",
          notes: [
            "Uses the built-in list implicit.",
            "The accent variant keeps the active row visually stronger when focused."
          ]
        }
      ],
      notes: [
        "Uses the built-in list implicit.",
        "The preview starts with the list unfocused so the muted rows are visible.",
        "Focus the list to restore the active selected-row highlight."
      ],
      source: "<.list id=\"languages\" variant=\"muted\" class=\"width-full height-8\">...</.list>"
    }
  end

  def render(assigns) do
    variant = Map.get(assigns, :__breeze_story_variant__, "accent")
    assigns = assign(assigns, languages: [variant | ~w(Elixir Erlang Gleam Rust Go Zig Lua Haskell)], variant: variant)

    ~H"""
    <.list
      id={"storybook-list-#{@variant}"}
      variant={@variant}
      list-initial-index={1}
      class="width-full height-8 bg-panel focus:border-primary"
    >
      <:item :for={language <- @languages} value={String.downcase(language)}>{language}</:item>
    </.list>
    """
  end
end
