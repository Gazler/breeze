defmodule Breeze.Storybook.Stories.Blocks.CheckboxStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "checkbox",
      title: "Checkbox",
      description: "Two-state checkbox with mouse and keyboard activation.",
      notes: [
        "A first left click focuses and toggles the checkbox.",
        "Press Space to toggle the focused checkbox.",
        "Disabled controls use ⟦ ⟧ or ⟦x⟧ in addition to muted styling.",
        "The checked value is stored in story-local state through br-change."
      ],
      source:
        ~s|<.checkbox id="mouse" checked={@mouse} br-change="mouse_changed">Mouse</.checkbox>|
    }
  end

  def mount(_opts, term) do
    {:ok,
     term
     |> assign(mouse: true, inspector: false)
     |> focus("storybook-checkbox-mouse")}
  end

  def render(assigns) do
    ~H"""
    <box class="w-full bg-panel">
      <box class="text-muted">Click once or press Space to toggle.</box>
      <box class="pt-1 h-2">
        <.checkbox id="storybook-checkbox-mouse" checked={@mouse} br-change="storybook_mouse_changed">
          Mouse input
        </.checkbox>
      </box>
      <box class="h-1">
        <.checkbox
          id="storybook-checkbox-inspector"
          checked={@inspector}
          br-change="storybook_inspector_changed"
        >
          Inspector
        </.checkbox>
      </box>
      <box class="h-1">
        <.checkbox id="storybook-checkbox-disabled" checked disabled>Unavailable</.checkbox>
      </box>
    </box>
    """
  end

  def handle_event("storybook_mouse_changed", %{value: value}, term) do
    {:noreply, assign(term, mouse: value)}
  end

  def handle_event("storybook_inspector_changed", %{value: value}, term) do
    {:noreply, assign(term, inspector: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
