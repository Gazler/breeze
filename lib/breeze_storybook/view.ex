defmodule Breeze.Storybook do
  @moduledoc """
  Root view for the interactive Breeze Storybook browser.

  Start it like any other Breeze application and pass Storybook configuration
  through `:start_opts`:

      Breeze.Server.start_link(
        view: Breeze.Storybook,
        start_opts: [directory: "storybook"]
      )

  The supported options are:

    * `:directory` - directory containing story files. Defaults to
      `"storybook"`.
    * `:file` - optional story file to load instead of scanning the directory.
  """

  use Breeze.View
  import Breeze.Blocks

  alias Breeze.Storybook.Registry

  @impl Breeze.View
  def mount(opts, term) do
    story_directory = Keyword.get(opts, :directory, "storybook")
    story_file = Keyword.get(opts, :file)
    registry_opts = storybook_registry_opts(story_file)
    stories = Registry.stories(story_directory, registry_opts)
    current = Registry.first_story(story_directory, registry_opts)

    {:ok,
     term
     |> switch_theme(theme_id(term.theme_source || term.theme))
     |> Map.put(:global_keybindings, storybook_global_keybindings())
     |> assign(
       story_directory: story_directory,
       story_file: story_file,
       stories: stories,
       current_story_id: current && current.id,
       current_variant_id: first_variant_id(current),
       show_debug: false
     )
     |> focus("storybook-nav")
     |> sync_storybook_layout()}
  end

  @impl Breeze.View
  def render(assigns) do
    current_story = current_story(assigns)
    current_variant = current_variant(current_story, assigns[:current_variant_id])
    variants = Map.get(current_story, :variants, [])
    variant_tabs? = variants != []

    assigns =
      assign(assigns,
        current_story: current_story,
        current_variant: current_variant,
        nav_title: "Storybook",
        preview_title: preview_title(current_story, current_variant),
        details_title: "Story Details",
        variants: variants,
        variant_tabs?: variant_tabs?,
        story_description: variant_field(current_variant, current_story, :description),
        story_notes: variant_field(current_variant, current_story, :notes),
        story_note_rows:
          variant_field(current_variant, current_story, :notes) |> Enum.with_index(),
        story_source: variant_field(current_variant, current_story, :source),
        preview_story_assigns: preview_story_assigns(assigns[:current_variant_id]),
        preview_story_top: if(variant_tabs?, do: 3, else: 2)
      )

    ~H"""
    <box class="width-screen height-screen bg">
      <box class="inline width-full height-full padding-left-1 padding-right-1">
        <.panel id="storybook-nav-panel" class="width-24 height-full">
          <:title>{@nav_title}</:title>
          <box class="width-full height-full overflow-hidden">
            <.list
              id="storybook-nav"
              variant="muted"
              br-change="select_story"
              list-selected={@current_story_id}
              class="height-full border-0 focus:border-0"
            >
              <:item :for={story <- @stories} value={story.id}>{story.title}</:item>
            </.list>
          </box>
        </.panel>
        <box class="bg-panel width-full height-full">
          <.panel
            id="storybook-preview-panel"
            class={"width-full height-#{@preview_panel_height}"}
            focus_within={false}
          >
            <:title>{@preview_title}</:title>
            <box class="width-full height-full bg-panel overflow-hidden">
              <box
                class={"absolute left-0 top-0 width-full height-#{@preview_panel_height - 2} bg-panel overflow-hidden"}
              >
                <box :if={@variant_tabs?} class="width-full">
                  <.tabs
                    id="storybook-variant-tabs"
                    selected={@current_variant.id}
                    variant="underline"
                    panel={false}
                    br-change="select_variant"
                    class="width-full height-2 bg-panel"
                  >
                    <:tab :for={variant <- @variants} value={variant.id} label={variant.label}>
                      <box>
                      </box>
                    </:tab>
                  </.tabs>
                </box>
                <box class="text-muted">{@story_description}</box>
                <box
                  class={"absolute left-0 top-#{@preview_story_top} width-#{@preview_story_width} height-#{@preview_story_height} overflow-hidden bg-panel"}
                >
                  <live
                    id="storybook-preview"
                    view={@current_story.module}
                    start_opts={[directory: @current_story.directory, file: @current_story.file]}
                    assigns={@preview_story_assigns}
                    class={"width-#{@preview_story_width} height-#{@preview_story_height} bg-panel"}
                  >
                  </live>
                </box>
              </box>
            </box>
          </.panel>
          <.panel id="storybook-details" class="width-full height-full" focus_within={false}>
            <:title>{@details_title}</:title>
            <box
              id="storybook-details-scroll"
              implicit={Breeze.Implicit.Scroll}
              class="width-full height-full bg-panel overflow-scroll scrollbar-arrows"
            >
              <box class="bold width-full">Description</box>
              <box id="storybook-detail-description" class="text-muted width-full">
                {@story_description}
              </box>
              <box>
              </box>
              <box class="text-muted width-full">Group: {@current_story.group}</box>
              <box class="text-muted width-full">Module: {inspect(@current_story.module)}</box>
              <box :if={@story_source} class="text-muted width-full">Source:</box>
              <box :if={@story_source} id="storybook-detail-source" class="text-muted width-full">
                {@story_source}
              </box>
              <box>
              </box>
              <box class="bold width-full">Notes</box>
              <box
                :for={{note, index} <- @story_note_rows}
                id={"storybook-detail-note-#{index}"}
                class="text-muted width-full"
              >
                • {note}
              </box>
              <box :if={@story_notes == []} class="text-muted width-full">No notes yet.</box>
            </box>
          </.panel>
        </box>
      </box>
      <box :if={@show_debug} class="fixed right-0 bottom-0 width-42 height-24 layer-50">
        <live
          id="debug"
          view={Breeze.Debug}
          start_opts={[width: 42, height: 24]}
          class="width-full height-full"
        >
        </live>
      </box>
    </box>
    """
  end

  @impl Breeze.View
  def handle_event("select_story", %{value: story_id}, term) do
    story =
      Registry.story(
        story_id,
        term.assigns.story_directory,
        storybook_registry_opts(term.assigns[:story_file])
      )

    {:noreply,
     term
     |> assign(current_story_id: story_id, current_variant_id: first_variant_id(story))
     |> sync_storybook_layout()}
  end

  def handle_event("select_variant", %{value: variant_id}, term) do
    {:noreply, term |> assign(current_variant_id: variant_id) |> sync_storybook_layout()}
  end

  def handle_event(_, %{"key" => "F2"}, term) do
    {:noreply, assign(term, show_debug: !term.assigns.show_debug)}
  end

  def handle_event(_, %{"key" => "F3"}, term) do
    {:noreply, cycle_storybook_theme(term) |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "ArrowLeft"}, term) do
    {:noreply,
     term |> step_variant(-1) |> focus("storybook-variant-tabs") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "h"}, term) do
    {:noreply,
     term |> step_variant(-1) |> focus("storybook-variant-tabs") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "ArrowRight"}, term) do
    {:noreply,
     term |> step_variant(1) |> focus("storybook-variant-tabs") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "l"}, term) do
    {:noreply,
     term |> step_variant(1) |> focus("storybook-variant-tabs") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "ArrowUp"}, term) do
    {:noreply, term |> step_story(-1) |> focus("storybook-nav") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "k"}, term) do
    {:noreply, term |> step_story(-1) |> focus("storybook-nav") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "ArrowDown"}, term) do
    {:noreply, term |> step_story(1) |> focus("storybook-nav") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => "j"}, term) do
    {:noreply, term |> step_story(1) |> focus("storybook-nav") |> sync_storybook_layout()}
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}

  def handle_event(_change, _event, term), do: {:noreply, sync_storybook_layout(term)}

  @impl Breeze.View
  def handle_info(_message, term), do: {:noreply, sync_storybook_layout(term)}

  defp current_story(assigns) do
    Enum.find(assigns.stories, &(&1.id == assigns.current_story_id)) ||
      Registry.first_story(assigns.story_directory, storybook_registry_opts(assigns[:story_file]))
  end

  defp current_variant(story, current_variant_id) do
    variants = Map.get(story, :variants, [])

    Enum.find(variants, &(&1.id == current_variant_id)) ||
      List.first(variants) ||
      %{id: nil, label: nil}
  end

  defp first_variant_id(nil), do: nil

  defp first_variant_id(story) do
    story
    |> Map.get(:variants, [])
    |> List.first()
    |> case do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp variant_field(variant, story, field) do
    case variant do
      %{id: id} when not is_nil(id) and field in [:notes] ->
        Map.get(variant, field, [])

      %{id: id} when not is_nil(id) and field in [:source] ->
        Map.get(variant, field)

      %{id: id} when not is_nil(id) ->
        Map.get(variant, field, Map.get(story, field))

      _ ->
        Map.get(story, field)
    end
  end

  defp preview_story_assigns(nil), do: %{}
  defp preview_story_assigns(variant_id), do: %{__breeze_story_variant__: variant_id}

  defp preview_title(story, %{label: nil}), do: "Preview: #{story.title}"
  defp preview_title(story, variant), do: "Preview: #{story.title} / #{variant.label}"

  defp storybook_global_keybindings do
    [
      {"F2", &handle_storybook_global_key/2},
      {"F3", &handle_storybook_global_key/2},
      {"ArrowLeft", &handle_storybook_global_key/2},
      {"h", &handle_storybook_global_key/2},
      {"ArrowRight", &handle_storybook_global_key/2},
      {"l", &handle_storybook_global_key/2},
      {"ArrowUp", &handle_storybook_global_key/2},
      {"k", &handle_storybook_global_key/2},
      {"ArrowDown", &handle_storybook_global_key/2},
      {"j", &handle_storybook_global_key/2}
    ]
  end

  defp handle_storybook_global_key(%{"ctrlKey" => true, "key" => key}, term)
       when key in ["ArrowLeft", "h"] do
    {:noreply,
     term |> step_variant(-1) |> focus("storybook-variant-tabs") |> sync_storybook_layout()}
  end

  defp handle_storybook_global_key(%{"ctrlKey" => true, "key" => key}, term)
       when key in ["ArrowRight", "l"] do
    {:noreply,
     term |> step_variant(1) |> focus("storybook-variant-tabs") |> sync_storybook_layout()}
  end

  defp handle_storybook_global_key(%{"ctrlKey" => true, "key" => key}, term)
       when key in ["ArrowUp", "k"] do
    {:noreply, term |> step_story(-1) |> focus("storybook-nav") |> sync_storybook_layout()}
  end

  defp handle_storybook_global_key(%{"ctrlKey" => true, "key" => key}, term)
       when key in ["ArrowDown", "j"] do
    {:noreply, term |> step_story(1) |> focus("storybook-nav") |> sync_storybook_layout()}
  end

  defp handle_storybook_global_key(%{"key" => "F2"}, term) do
    {:noreply, assign(term, show_debug: !term.assigns.show_debug)}
  end

  defp handle_storybook_global_key(%{"key" => "F3"}, term) do
    {:noreply, cycle_storybook_theme(term) |> sync_storybook_layout()}
  end

  defp handle_storybook_global_key(_event, _term), do: :continue

  defp cycle_storybook_theme(term) do
    term = Breeze.View.cycle_theme(term)

    term
    |> put_preview_child_theme(term.theme_source)
  end

  defp put_preview_child_theme(term, theme) do
    Enum.each(term.children, fn
      {_id, %{pid: pid}} when is_pid(pid) ->
        if Process.alive?(pid) do
          :ok =
            Breeze.ChildServer.put_theme(pid, theme,
              apply_theme_defaults?: term.apply_theme_defaults?,
              notify?: false
            )
        end

      _child ->
        :ok
    end)

    term
  end

  defp theme_id(%Breeze.Theme{name: "nebula"}), do: :nebula
  defp theme_id(%Breeze.Theme{name: "catppuccin-mocha"}), do: :catppuccin
  defp theme_id(%Breeze.Theme{name: "dracula"}), do: :dracula
  defp theme_id(%Breeze.Theme{name: "gruvbox-dark"}), do: :gruvbox
  defp theme_id(%Breeze.Theme{name: "nord"}), do: :nord
  defp theme_id(%Breeze.Theme{name: "solarized-light"}), do: :solarized_light
  defp theme_id(%Breeze.Theme{name: "solarized-dark"}), do: :solarized_dark
  defp theme_id(%Breeze.Theme{mode: :system16}), do: :system16
  defp theme_id(:system16), do: :system16
  defp theme_id(:system), do: :system
  defp theme_id(_theme), do: :gruvbox

  defp step_story(term, delta) do
    stories = term.assigns.stories
    current_story_id = term.assigns.current_story_id
    count = length(stories)

    if count == 0 do
      term
    else
      current_index = Enum.find_index(stories, &(&1.id == current_story_id)) || 0
      next_index = rem(current_index + delta + count, count)
      story = Enum.at(stories, next_index)

      assign(
        term,
        current_story_id: story.id,
        current_variant_id: first_variant_id(story)
      )
    end
  end

  defp step_variant(term, delta) do
    story =
      Enum.find(term.assigns.stories, &(&1.id == term.assigns.current_story_id)) ||
        Registry.first_story(
          term.assigns.story_directory,
          storybook_registry_opts(term.assigns[:story_file])
        )

    variants = Map.get(story, :variants, [])
    count = length(variants)

    if count == 0 do
      term
    else
      current_variant_id = term.assigns.current_variant_id
      current_index = Enum.find_index(variants, &(&1.id == current_variant_id)) || 0
      next_index = rem(current_index + delta + count, count)
      variant = Enum.at(variants, next_index)
      assign(term, current_variant_id: variant.id)
    end
  end

  defp sync_storybook_layout(term) do
    {screen_width, screen_height} =
      case term.terminal do
        %Termite.Terminal{size: %{width: width, height: height}} -> {width, height}
        _ -> {80, 24}
      end

    current_story =
      term.assigns
      |> Map.take([:stories, :current_story_id, :story_directory, :story_file])
      |> current_story()

    preview_panel_width = max(screen_width - 27, 20)
    variant_rows = if Map.get(current_story, :variants, []) == [], do: 0, else: 1
    preview_panel_height = max(div(screen_height, 2), 10)
    preview_story_width = max(preview_panel_width - 2, 1)
    preview_story_height = max(preview_panel_height - 4 - variant_rows, 1)

    assign(term,
      preview_panel_height: preview_panel_height,
      preview_story_width: preview_story_width,
      preview_story_height: preview_story_height
    )
  end

  defp storybook_registry_opts(nil), do: []
  defp storybook_registry_opts(file), do: [file: file]
end
