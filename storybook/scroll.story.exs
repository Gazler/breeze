defmodule Breeze.Storybook.Stories.Blocks.ScrollStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "scroll",
      title: "Scroll",
      description: "Scrollable content region with keyboard and scrollbar support.",
      notes: [
        "The preview content is taller than the viewport so the scrollbar is visible."
      ],
      source: "<.scroll id=\"logs\">...</.scroll>"
    }
  end

  def render(_story) do
    assigns = %{lines: Enum.map(1..12, &"Log line #{&1}")}

    ~H"""
    <.scroll id="storybook-scroll" class="w-40 h-7 bg-panel focus:scrollbar-primary">
      <box :for={line <- @lines}>{line}</box>
    </.scroll>
    """
  end
end
