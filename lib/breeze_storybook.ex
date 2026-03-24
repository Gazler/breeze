defmodule Breeze.Storybook do
  @moduledoc """
  Storybook helpers for browsing Breeze components in a dedicated TUI.
  """

  alias Breeze.Storybook.Registry

  def stories do
    Registry.stories()
  end

  def story(id) do
    Registry.story(id)
  end

  def story_modules do
    Registry.story_modules()
  end
end
