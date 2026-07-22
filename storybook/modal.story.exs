defmodule Breeze.Storybook.Stories.Blocks.ModalStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "modal",
      title: "Modal",
      description: "Centered modal container with optional dimmed backdrop.",
      variants: [
        %{
          id: "dim",
          label: "Dim",
          source: "<.modal id=\"confirm\" width={32} height={10} dim>...</.modal>",
          notes: [
            "The preview starts from the trigger state so the shell focus stays intact.",
            "Press Enter on the trigger to open the real modal in place.",
            "This variant dims the backdrop behind the modal."
          ]
        },
        %{
          id: "regular",
          label: "Regular",
          description: "Centered modal container without a dimmed backdrop.",
          source: "<.modal id=\"confirm\" width={32} height={10}>...</.modal>",
          notes: [
            "The preview starts from the trigger state so the shell focus stays intact.",
            "Press Enter on the trigger to open the real modal in place.",
            "This variant keeps the backdrop at the normal panel tone."
          ]
        }
      ],
      notes: [
        "The preview starts from the trigger state so the shell focus stays intact.",
        "Press Enter on the trigger to open the real modal in place."
      ],
      source: "<.modal id=\"confirm\" width={32} height={10} dim>...</.modal>"
    }
  end

  def mount(_opts, term) do
    {:ok, assign(term, show_modal: false)}
  end

  def render(assigns) do
    assigns = assign(assigns, dim?: Map.get(assigns, :__breeze_story_variant__, "dim") == "dim")

    ~H"""
    <box class="w-full h-full bg">
      <box
        id="storybook-modal-trigger"
        class="absolute left-2 top-1 w-20 h-3 rounded focus:border-primary"
        focusable
      >
        <box class="font-bold text-center">Open Modal</box>
      </box>
      <.modal
        :if={@show_modal}
        id="storybook-modal"
        width={32}
        height={10}
        dim={@dim?}
        br-change="storybook_close_modal"
      >
        <:title>Confirm Action</:title>
        <box class="w-full">Interactive modal inside the preview.</box>
        <box class="w-full">Escape closes it normally.</box>
        <box>
        </box>
        <box
          id="storybook-modal-close"
          focusable
          default-focus
          class="w-16 h-3 rounded focus:border-primary"
        >
          <box class="font-bold text-center">Close</box>
        </box>
      </.modal>
    </box>
    """
  end

  def handle_event("storybook_close_modal", _params, term) do
    {:noreply, assign(term, show_modal: false)}
  end

  def handle_event(_, %{"key" => key}, %{focused: "storybook-modal-trigger"} = term)
      when key in ["Enter", " "] do
    {:noreply, assign(term, show_modal: true)}
  end

  def handle_event(
        _,
        %{"key" => key},
        %{assigns: %{show_modal: true}, focused: "storybook-modal-close"} = term
      )
      when key in ["Enter", " "] do
    {:noreply, assign(term, show_modal: false)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
