defmodule Breeze.Storybook.Stories.Blocks.ButtonStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "button",
      title: "Button",
      description: "Primary action button with filled and bordered variants.",
      variants: [
        %{
          id: "default",
          label: "Default",
          description: "Compact filled action button with inverse focus styling.",
          source: ~s|<.button id="confirm" class="w-12">Confirm</.button>|,
          notes: [
            "The default variant is a compact one-row filled button.",
            "This story records Enter, Space, and left-button release with view-level event handling."
          ]
        },
        %{
          id: "bordered",
          label: "Bordered",
          description: "Three-row outlined action button with a full-width bottom focus edge.",
          source:
            ~s|<.button id="confirm" variant="bordered" class="w-12 text-center">Confirm</.button>|,
          notes: [
            "The bordered variant owns its height, rounded outline, and focused border color.",
            "Focus changes the full bottom stroke to an inward-facing edge while preserving the rounded corners.",
            "The destructive example uses the error color for both its outline and focus edge.",
            "This story records Enter, Space, and left-button release with view-level event handling."
          ]
        }
      ],
      notes: [
        "The button block is presentational and uses the normal focus and event lifecycle.",
        "This story records Enter, Space, and left-button release with view-level event handling."
      ],
      source: ~s|<.button id="confirm" class="w-12">Confirm</.button>|
    }
  end

  def mount(_opts, term) do
    {:ok, assign(term, latest_press: "None")}
  end

  def render(assigns) do
    variant = Map.get(assigns, :__breeze_story_variant__, "default")

    assigns =
      assign(assigns,
        button_variant: variant,
        button_class: if(variant == "bordered", do: "w-12 text-center", else: "w-12"),
        delete_class:
          if(variant == "bordered",
            do: "w-12 text-center border-error",
            else: "w-12 bg-error"
          )
      )

    ~H"""
    <box class="w-full bg-panel">
      <box class="text-muted">Click a button, or focus it and press Enter or Space.</box>
      <box class="pt-1 grid grid-cols-3 gap-x-1">
        <.button id="storybook-button-primary" variant={@button_variant} class={@button_class}>
          Confirm
        </.button>
        <.button id="storybook-button-cancel" variant={@button_variant} class={@button_class}>
          Cancel
        </.button>
        <.button
          id="storybook-button-delete"
          variant={@button_variant}
          highlight="error"
          class={@delete_class}
        >
          Delete
        </.button>
      </box>
      <box class="pt-1">Latest press: {@latest_press}</box>
    </box>
    """
  end

  def handle_event(_, %{"key" => key}, %{focused: focused} = term)
      when key in ["Enter", " "] do
    record_press(focused, term)
  end

  def handle_event(
        _,
        %{
          "mouse" => %{"button" => "left", "action" => "release"},
          "target" => target
        },
        term
      ) do
    record_press(target, term)
  end

  def handle_event(_, _, term), do: {:noreply, term}

  defp record_press("storybook-button-primary", term),
    do: {:noreply, assign(term, latest_press: "Confirm")}

  defp record_press("storybook-button-cancel", term),
    do: {:noreply, assign(term, latest_press: "Cancel")}

  defp record_press("storybook-button-delete", term),
    do: {:noreply, assign(term, latest_press: "Delete")}

  defp record_press(_, term), do: {:noreply, term}
end
