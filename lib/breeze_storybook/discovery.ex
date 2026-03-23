defmodule Breeze.Storybook.Discovery do
  @moduledoc """
  Read-only discovery helpers for introspecting available Breeze components.
  """

  @helper_functions [
    :__breeze_component__,
    :inline_style,
    :merge_class,
    :merge_style,
    :tab_indicator_class,
    :tab_item_class
  ]

  def components(module \\ Breeze.Blocks) do
    module.__info__(:functions)
    |> Enum.filter(fn {name, arity} ->
      arity == 1 and name not in @helper_functions
    end)
    |> Enum.map(fn {name, arity} ->
      %{
        id: Atom.to_string(name),
        name: name,
        arity: arity,
        module: module
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  def undocumented_components(stories, module \\ Breeze.Blocks) do
    story_ids = MapSet.new(Enum.map(stories, & &1.id))

    components(module)
    |> Enum.reject(&MapSet.member?(story_ids, &1.id))
  end
end
