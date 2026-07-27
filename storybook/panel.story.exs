defmodule Breeze.Storybook.Stories.Blocks.PanelStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "panel",
      title: "Panel",
      description: "Bordered surface with a title slot and padded content.",
      notes: [
        "Panels are useful as the main layout primitive for grouping content in larger TUIs."
      ],
      source: "<.panel id=\"details\" title=\"Details\">...</.panel>"
    }
  end

  def render(_story) do
    assigns = %{}

    ~H"""
    <.panel id="storybook-panel" class="w-42 h-8">
      <:title>Details</:title>
      <box>Status: Draft</box>
      <box>Owner: Storybook</box>
      <box class="text-muted w-full">Panels compose cleanly with scrolls, lists, and forms.</box>
    </.panel>
    """
  end
end
