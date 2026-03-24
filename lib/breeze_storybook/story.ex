defmodule Breeze.Storybook.Story do
  @moduledoc """
  Behaviour for a single storybook entry.
  """

  @callback story() :: map()
  @callback render(map()) :: term()
  @callback render_overlay(map()) :: term() | nil

  defmacro __using__(_opts) do
    quote do
      use Breeze.View
      import Breeze.Blocks

      @behaviour Breeze.Storybook.Story

      def group, do: "Blocks"
      def notes, do: []
      def source, do: nil
      def render_overlay(_assigns), do: nil
      def mount(_opts, term), do: {:ok, term}
      def handle_event(_, _, term), do: {:noreply, term}
      def handle_info(_, term), do: {:noreply, term}

      defoverridable group: 0,
                     notes: 0,
                     source: 0,
                     render_overlay: 1,
                     mount: 2,
                     handle_event: 3,
                     handle_info: 2
    end
  end
end
