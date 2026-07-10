defmodule Breeze.Storybook.Story do
  @moduledoc """
  Defines a Storybook entry.

  A story is a normal `Breeze.View` with a `story/0` metadata callback:

      defmodule MyApp.ButtonStory do
        use Breeze.Storybook.Story

        def story do
          %{
            id: "button",
            title: "Button",
            description: "Primary action button",
            source: ~s|<.button id="save">Save</.button>|,
            notes: ["Use a view event to handle activation."]
          }
        end

        def render(assigns), do: ~H"<.button id=\"save\">Save</.button>"
      end

  Story metadata supports `:id`, `:title`, `:group`, `:description`, `:source`,
  `:notes`, and `:variants`. A variant is a map with an `:id` and `:label` and
  can override `:description`, `:source`, and `:notes`.
  """

  @doc "Returns the metadata used to list and describe the story."
  @callback story() :: map()

  defmacro __using__(_opts) do
    quote do
      use Breeze.View
      import Breeze.Blocks

      @behaviour Breeze.Storybook.Story

      def group, do: "Blocks"
      def notes, do: []
      def source, do: nil
      def mount(_opts, term), do: {:ok, term}
      def handle_event(_, _, term), do: {:noreply, term}
      def handle_info(_, term), do: {:noreply, term}

      defoverridable group: 0,
                     notes: 0,
                     source: 0,
                     mount: 2,
                     handle_event: 3,
                     handle_info: 2
    end
  end
end
