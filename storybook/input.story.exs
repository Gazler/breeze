defmodule Breeze.Storybook.Stories.Blocks.InputStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "input",
      title: "Input",
      description: "Single-line input with placeholder and focused styling.",
      notes: [
        "Shows placeholder treatment and focused appearance.",
        "Both inputs are live so you can type into them inside the storybook."
      ],
      source:
        "<.input id=\"email\" input-placeholder=\"Email\" input-value=\"dev@example.com\" />"
    }
  end

  def mount(_opts, term) do
    {:ok, assign(term, email: "dev@example.com", placeholder_email: "")}
  end

  def render(assigns) do
    ~H"""
    <box class="w-full bg-panel">
      <box class="text-muted">Focused</box>
      <.input
        id="storybook-input-active"
        input-value={@email}
        br-change="storybook_input_active_changed"
        class="w-32"
      />
      <box class="pt-1">
        <box class="text-muted">Placeholder</box>
        <.input
          id="storybook-input-placeholder"
          input-value={@placeholder_email}
          input-placeholder="Email address"
          br-change="storybook_input_placeholder_changed"
          class="w-32"
        />
      </box>
    </box>
    """
  end

  def handle_event("storybook_input_active_changed", %{value: value}, term) do
    {:noreply, assign(term, email: value)}
  end

  def handle_event("storybook_input_placeholder_changed", %{value: value}, term) do
    {:noreply, assign(term, placeholder_email: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
