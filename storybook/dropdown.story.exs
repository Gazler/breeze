defmodule Breeze.Storybook.Stories.Blocks.DropdownStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "dropdown",
      title: "Dropdown",
      description: "Collapsed dropdown trigger with themed menu styling.",
      notes: [
        "Uses the real dropdown component.",
        "The selected value is stored in story-local state so it persists after selection."
      ],
      source: "<.dropdown id=\"method\" selected=\"POST\">...</.dropdown>"
    }
  end

  def mount(_opts, term) do
    {:ok, assign(term, method: "POST")}
  end

  def render(assigns) do
    ~H"""
    <.dropdown id="storybook-dropdown" selected={@method} br-change="storybook_dropdown_changed">
      <:item value="GET">GET</:item>
      <:item value="POST">POST</:item>
      <:item value="PUT">PUT</:item>
      <:item value="DELETE">DELETE</:item>
    </.dropdown>
    """
  end

  def handle_event("storybook_dropdown_changed", %{value: value}, term) do
    {:noreply, assign(term, method: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
