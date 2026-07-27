defmodule Breeze.Storybook.Stories.Blocks.MarkdownStory do
  use Breeze.Storybook.Story

  @content """
  # Release Notes

  Breeze renders **formatted text**, `inline code`, and wrapped paragraphs inside a scrollable block.

  - Headings and emphasis use terminal styling
  - Lists wrap to the configured content width
  - Links retain their readable label and URL

  ```elixir
  {:ok, term}
  ```

  Read the [Breeze documentation](https://hexdocs.pm/breeze) for more examples.
  """

  def story do
    %{
      id: "markdown",
      title: "Markdown",
      description: "Scrollable terminal rendering for headings, lists, links, and code.",
      notes: [
        "The width attribute controls wrapping inside the rendered Markdown content.",
        "The component uses the regular scroll implicit, so focused arrow and page keys scroll longer documents."
      ],
      source: ~S(<.markdown id="release-notes" content={@content} width={44} />)
    }
  end

  def render(_story) do
    assigns = %{content: @content}

    ~H"""
    <.markdown
      id="storybook-markdown"
      content={@content}
      width={44}
      class="w-46 h-full bg-panel focus:scrollbar-primary"
    />
    """
  end
end
