defmodule Breeze.Storybook.Stories.Blocks.ButtonStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "button",
      title: "Button",
      description: "Primary action button with focus styling.",
      notes: [
        "This block is presentational and uses the normal focus and event lifecycle.",
        "Use view-level event handling to decide what Enter or Space should do when the button is focused."
      ],
      source: ~s|<.button id="confirm" class="width-10">Confirm</.button>|
    }
  end

  def render(assigns) do
    ~H"""
    <box class="width-full bg-panel">
      <box class="text-muted">Focused primary action</box>
      <box class="padding-top-1 grid grid-cols-3 gap-x-1">
        <.button id="storybook-button-primary" class="width-10">Confirm</.button>
        <.button id="storybook-button-cancel" class="width-10">Cancel</.button>
        <.button id="storybook-button-delete" class="width-10 bg-error">Delete</.button>
      </box>
    </box>
    """
  end
end
