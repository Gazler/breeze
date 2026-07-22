defmodule Breeze.Storybook.Stories.Blocks.TextareaStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "textarea",
      title: "Textarea",
      description: "Multiline textarea with default and prompt-style variants.",
      notes: [
        "The default bordered textarea grows with each logical line up to a capped height.",
        "The prompt-style example shows how `textarea-prefix` and `border-none` can be combined.",
        "Use Enter to insert new lines in the focused textarea."
      ],
      source:
        "<.textarea id=\"composer\" textarea-placeholder=\"Ask anything\" textarea-value={@message} />"
    }
  end

  def mount(_opts, term) do
    {:ok,
     term
     |> assign(
       message: "Summarize routing changes.\nKeep migration notes short.",
       placeholder_message: ""
     )}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        message_line_count: line_count(assigns.message),
        message_height: textarea_height(assigns.message)
      )

    ~H"""
    <box class="w-full bg-panel">
      <box class="text-muted">Default</box>
      <.textarea
        id="storybook-textarea-active"
        textarea-value={@message}
        textarea-placeholder="Ask anything"
        br-change="storybook_textarea_active_changed"
        class={"w-40 h-#{@message_height}"}
      />
      <box class="pt-1 text-muted">
        height={@message_height} lines={@message_line_count} cursor={String.length(@message)}
      </box>
      <box class="pt-1 text-muted">Prompt Style</box>
      <.textarea
        id="storybook-textarea-placeholder"
        textarea-value={@placeholder_message}
        textarea-placeholder="Ask anything"
        textarea-prefix="› "
        br-change="storybook_textarea_placeholder_changed"
        class="w-full bg-surface pl-0 pt-1 pb-1 border-none"
      />
    </box>
    """
  end

  def handle_event("storybook_textarea_active_changed", %{value: value}, term) do
    {:noreply, assign(term, message: value)}
  end

  def handle_event("storybook_textarea_placeholder_changed", %{value: value}, term) do
    {:noreply, assign(term, placeholder_message: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  defp textarea_height(value) do
    value
    |> line_count()
    |> Kernel.+(2)
    |> min(7)
    |> max(4)
  end

  defp line_count(value) do
    value
    |> String.split("\n", trim: false)
    |> length()
  end
end
