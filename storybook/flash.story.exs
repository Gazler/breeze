defmodule Breeze.Storybook.Stories.Blocks.FlashStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "flash",
      title: "Flash",
      description: "Overlay flash messages that stack from a screen corner.",
      variants: [
        %{
          id: "default",
          label: "Default",
          source: ~S(<.flash_group flash={@breeze.flash} />),
          notes: [
            "Default flash messages use a compact square-corner panel with a left highlight strip."
          ]
        },
        %{
          id: "square",
          label: "Square",
          source: ~S(<.flash_group flash={@breeze.flash} variant="square" />),
          notes: [
            "The square variant uses block glyphs for the frame and keeps the highlight inside the message."
          ]
        },
        %{
          id: "rounded",
          label: "Rounded",
          source: ~S(<.flash_group flash={@breeze.flash} variant="rounded" />),
          notes: [
            "The rounded variant uses the normal rounded border style with the same flash stack behavior."
          ]
        }
      ],
      notes: [
        "Use Breeze.View.put_flash/4 to append messages and Breeze.View.clear_flash/1 or /2 to remove them.",
        "Managed flash messages live in the Breeze namespace at @breeze.flash.",
        "Each message can set a custom highlight color for the left column, including semantic tokens, ANSI indexes, RGB tuples, and hex strings.",
        "Set variant=\"square\" or variant=\"rounded\" on the group to change the panel border."
      ],
      source: ~S(<.flash_group flash={@breeze.flash} />)
    }
  end

  def render(story) do
    variant = Map.get(story, :__breeze_story_variant__, "default")

    assigns = %{
      variant: variant,
      breeze: %{
        flash: [
          %{
            id: "storybook-flash-info",
            kind: :info,
            message: "Settings saved",
            highlight: "#6bc2ff"
          },
          %{
            id: "storybook-flash-success",
            kind: :success,
            title: "Deploy queued",
            message: "Worker picked up the release",
            highlight: {184, 187, 38}
          }
        ]
      }
    }

    ~H"""
    <box class="width-full height-full bg">
      <box class="width-full bold">Flash Preview</box>
      <box class="width-50 text-muted">
        The flash stack is fixed to the bottom-right corner and does not affect layout.
      </box>
      <box class="padding-top-1 width-42">
        <box>Status: Ready</box>
        <box>Queue: 3 jobs</box>
        <box>Region: eu-west</box>
      </box>
      <.flash_group flash={@breeze.flash} variant={@variant}/>
    </box>
    """
  end
end
