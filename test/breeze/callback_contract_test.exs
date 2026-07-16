defmodule Breeze.CallbackContractTest do
  use ExUnit.Case, async: true

  defmodule ContractView do
    use Breeze.View

    def render(assigns), do: ~H"<box>contract</box>"
  end

  defmodule ContractComponent do
    use Breeze.Component

    attr :label, :string, default: "component"

    def badge(assigns), do: ~H"<box>{@label}</box>"
    def render(assigns), do: ~H"<.badge/>"
  end

  defmodule ContractStory do
    use Breeze.Storybook.Story

    def story, do: %{}
    def render(assigns), do: ~H"<box>story</box>"
  end

  @implicit_modules [
    Breeze.Implicit.AsyncSpinner,
    Breeze.Implicit.Dropdown,
    Breeze.Implicit.Input,
    Breeze.Implicit.List,
    Breeze.Implicit.Modal,
    Breeze.Implicit.Scroll,
    Breeze.Implicit.Tabs,
    Breeze.Implicit.Textarea,
    Breeze.Implicit.Tree
  ]

  test "using Breeze.View declares the view behaviour" do
    assert Breeze.View in behaviours(ContractView)

    assert {:mount, 2} in Breeze.View.behaviour_info(:callbacks)
    assert {:render, 1} in Breeze.View.behaviour_info(:callbacks)
    assert {:handle_event, 3} in Breeze.View.behaviour_info(:callbacks)
    assert {:handle_info, 2} in Breeze.View.behaviour_info(:callbacks)
  end

  test "using Breeze.Component provides templates without the view lifecycle" do
    refute Breeze.View in behaviours(ContractComponent)
    assert ContractComponent.__breeze_components__() == [:badge]

    assert Breeze.Renderer.render_to_string(ContractComponent, %{}) =~ "component"
  end

  test "a story is also a view and only adds its story callback" do
    assert Breeze.View in behaviours(ContractStory)
    assert Breeze.Storybook.Story in behaviours(ContractStory)

    callbacks = Breeze.Storybook.Story.behaviour_info(:callbacks)

    assert {:story, 0} in callbacks
    refute {:render, 1} in callbacks
    refute {:render_overlay, 1} in callbacks
  end

  test "built-in implicit modules declare the implicit behaviour" do
    refute {:init, 2} in Breeze.Implicit.behaviour_info(:callbacks)
    assert {:init, 3} in Breeze.Implicit.behaviour_info(:callbacks)
    assert {:handle_event, 3} in Breeze.Implicit.behaviour_info(:callbacks)
    assert {:handle_modifiers, 3} in Breeze.Implicit.behaviour_info(:callbacks)
    assert {:animate, 5} in Breeze.Implicit.behaviour_info(:callbacks)

    for module <- @implicit_modules do
      assert Breeze.Implicit in behaviours(module)
      assert function_exported?(module, :init, 3)
      refute function_exported?(module, :init, 2)
      assert function_exported?(module, :handle_modifiers, 3)
    end
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
