defmodule Breeze.Storybook.View do
  use Breeze.View
  import Breeze.Blocks

  alias Breeze.Storybook.Discovery
  alias Breeze.Storybook.Registry

  def mount(opts, term) do
    story_directory = Keyword.get(opts, :directory, "storybook")
    stories = Registry.stories(story_directory)
    current = Registry.first_story(story_directory)

    {:ok,
     term
     |> focus("storybook-nav")
     |> sync_storybook_layout()
     |> assign(
       story_directory: story_directory,
       stories: stories,
       current_story_id: current && current.id,
       discovered_components: Discovery.components(),
       undocumented_components: Discovery.undocumented_components(stories)
     )}
  end

  def render(assigns) do
    current_story = current_story(assigns)

    assigns =
      assign(assigns,
        current_story: current_story,
        nav_title: "Storybook",
        preview_title: "Preview: #{current_story.title}",
        details_title: "Story Details",
        inventory_summary: inventory_summary(assigns.undocumented_components)
      )

    ~H"""
    <box class="width-screen height-screen bg padding-left-1 padding-right-1">
      <box class="inline width-full height-full">
        <.panel id="storybook-nav-panel" class="width-24 height-full">
          <:title>{@nav_title}</:title>
          <box
            id="storybook-nav"
            implicit={Breeze.Implicit.List}
            focusable
            br-change="select_story"
            list-selected={@current_story_id}
            list-scroll-padding={1}
            class="height-full overflow-scroll scrollbar-arrows focus:scrollbar-primary"
          >
            <box
              :for={story <- @stories}
              value={story.id}
              class="selected:bg-primary selected:text-bg focus:selected:bg-accent width-full"
            >
              {story.title}
            </box>
          </box>
        </.panel>
        <box class="bg-panel width-full height-full">
          <.panel id="storybook-preview-panel" class={"width-full height-#{@preview_panel_height}"}>
            <:title>{@preview_title}</:title>
            <box class="absolute left-1 right-1 top-1 bottom-1 bg-panel">
              <box class="text-muted">{@current_story.description}</box>
              <box class="absolute left-0 right-0 top-2 bottom-0">
                <live
                  id="storybook-preview"
                  view={@current_story.module}
                  start_opts={[directory: @current_story.directory, file: @current_story.file]}
                  class={"width-#{@preview_story_width} height-#{@preview_story_height}"}
                >
                </live>
              </box>
            </box>
          </.panel>
          <.panel
            id="storybook-details"
            class="width-full height-full"
            scroll
            scroll_class="width-full height-full bg-panel focus:scrollbar-primary"
          >
            <:title>{@details_title}</:title>
            <box class="bold">Description</box>
            <box class="text-muted">{@current_story.description}</box>
            <box>
            </box>
            <box class="text-muted">Group: {@current_story.group}</box>
            <box class="text-muted">Module: {inspect(@current_story.module)}</box>
            <box :if={@current_story.source} class="text-muted">Source: {@current_story.source}</box>
            <box>
            </box>
            <box class="bold">Notes</box>
            <box :for={note <- @current_story.notes} class="text-muted">• {note}</box>
            <box :if={@current_story.notes == []} class="text-muted">No notes yet.</box>
            <box>
            </box>
            <box class="bold">Discovered Blocks</box>
            <box class="text-muted">{Enum.map_join(@discovered_components, ", ", & &1.id)}</box>
            <box>
            </box>
            <box class="bold">Missing Stories</box>
            <box class="text-muted">{@inventory_summary}</box>
          </.panel>
        </box>
      </box>
    </box>
    """
  end

  def handle_event("select_story", %{value: story_id}, term) do
    {:noreply,
     term
     |> sync_storybook_layout()
     |> assign(current_story_id: story_id)}
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}

  def handle_event(_change, _event, term), do: {:noreply, sync_storybook_layout(term)}

  def handle_info(_message, term), do: {:noreply, sync_storybook_layout(term)}

  defp current_story(assigns) do
    Enum.find(assigns.stories, &(&1.id == assigns.current_story_id)) ||
      Registry.first_story(assigns.story_directory)
  end

  defp inventory_summary([]), do: "All discovered Breeze.Blocks exports have stories."

  defp inventory_summary(components) do
    Enum.map_join(components, ", ", & &1.id)
  end

  defp sync_storybook_layout(term) do
    {screen_width, screen_height} =
      case term.terminal do
        %Termite.Terminal{size: %{width: width, height: height}} -> {width, height}
        _ -> {80, 24}
      end

    preview_panel_width = max(screen_width - 27, 20)
    preview_panel_height = max(div(screen_height, 2), 10)
    preview_story_width = max(preview_panel_width - 2, 1)
    preview_story_height = max(preview_panel_height - 4, 1)

    assign(term,
      preview_panel_height: preview_panel_height,
      preview_story_width: preview_story_width,
      preview_story_height: preview_story_height
    )
  end
end
