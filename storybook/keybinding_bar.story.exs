defmodule Breeze.Storybook.Stories.Blocks.KeybindingBarStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "keybinding-bar",
      title: "Keybinding Bar",
      description: "Compact footer hints for the controls active in the current view.",
      notes: [
        "Pass normalized keybinding maps containing a key and optional label.",
        "The bar highlights keys, uses the key as the fallback label, and clips cleanly in narrow layouts."
      ],
      source: ~S(<.keybinding_bar keybindings={@keybindings} />)
    }
  end

  def render(_story) do
    assigns = %{
      keybindings:
        Breeze.Keybindings.normalize_list([
          {"Enter", "Select"},
          {"↑/↓", "Navigate"},
          {"d", "Details"},
          {"q", "Quit"}
        ])
    }

    ~H"""
    <box class="w-full bg-panel">
      <box class="text-muted">Active keybindings</box>
      <box class="h-1 bg-surface overflow-hidden">
        <.keybinding_bar keybindings={@keybindings}/>
      </box>
    </box>
    """
  end
end
