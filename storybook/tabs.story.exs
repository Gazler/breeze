defmodule Breeze.Storybook.Stories.Blocks.TabsStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "tabs",
      title: "Tabs",
      description: "Underline tabs with live selection and panel content.",
      notes: [
        "The preview uses the underline variant because it exercises the recent tab indicator work.",
        "Selection is stored in story-local state so left/right navigation and tab changes are visible."
      ],
      source: "<.tabs id=\"request-tabs\" selected=\"headers\" variant=\"underline\">...</.tabs>"
    }
  end

  def mount(_opts, term) do
    {:ok, term |> assign(selected_tab: "headers") |> focus("storybook-tabs")}
  end

  def render(assigns) do
    ~H"""
    <box class="w-full bg-panel">
      <box class="text-muted">Use left/right arrows while the tabs are focused.</box>
      <box class="pt-1">
        <.tabs
          id="storybook-tabs"
          selected={@selected_tab}
          variant="underline"
          br-change="storybook_tabs_changed"
          class="w-40 h-8"
        >
          <:tab value="headers" label="Headers">
            <box class="text-muted">Request headers preview</box>
          </:tab>
          <:tab value="body" label="Body">
            <box class="text-muted">Request body preview</box>
          </:tab>
          <:tab value="auth" label="Auth">
            <box class="text-muted">Authentication settings</box>
          </:tab>
        </.tabs>
      </box>
    </box>
    """
  end

  def handle_event("storybook_tabs_changed", %{value: value}, term) do
    {:noreply, assign(term, selected_tab: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
