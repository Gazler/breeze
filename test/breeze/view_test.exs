defmodule Breeze.ViewTest do
  use ExUnit.Case, async: true

  import Breeze.View

  defmodule BreezeAssignsView do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>{@breeze.theme.name}/{@breeze.theme.actual_mode}/{@breeze.theme.status}</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  test "update_implicit updates an existing implicit state" do
    term = %{
      implicit_state: %{
        "dropdown" =>
          {Breeze.Implicit.Dropdown, %{open?: false, selected_index: 1, highlighted_index: 0}}
      }
    }

    updated =
      update_implicit(term, "dropdown", fn
        {Breeze.Implicit.Dropdown, state} -> Breeze.Implicit.Dropdown.open(state)
      end)

    assert {Breeze.Implicit.Dropdown, %{open?: true, highlighted_index: 1}} =
             updated.implicit_state["dropdown"]
  end

  test "update_implicit ignores missing implicits" do
    term = %{implicit_state: %{}}

    assert update_implicit(term, "missing", fn {_mod, state} -> state end) == term
  end

  test "put_local_keybindings and put_focus_keybindings normalize keybinding hints" do
    term = %Breeze.Term{assigns: %{}, local_keybindings: [], focus_keybindings: %{}}

    updated =
      term
      |> put_local_keybindings([{"q", "Quit"}])
      |> put_focus_keybindings("editor", [{"Enter", "Save"}])

    assert updated.local_keybindings == [%{key: "q", label: "Quit", handler: nil}]

    assert updated.focus_keybindings == %{
             "editor" => [%{key: "Enter", label: "Save", handler: nil}]
           }
  end

  test "switch_theme applies a named theme and standard Breeze metadata assigns" do
    term = %Breeze.Term{assigns: %{}}

    updated = switch_theme(term, :gruvbox)

    assert updated.assigns.breeze.theme == %{
             name: :gruvbox,
             actual_mode: :custom,
             status: :ready
           }

    assert updated.theme.name == "gruvbox-dark"
  end

  test "cycle_theme advances through the default theme cycle" do
    term =
      %Breeze.Term{assigns: %{}}
      |> switch_theme(:gruvbox)
      |> cycle_theme()

    assert term.assigns.breeze.theme.name == :nord
    assert term.theme.name == "nord"
  end

  test "cycle_theme can be used directly as a keybinding handler" do
    term = %Breeze.Term{assigns: %{}} |> switch_theme(:solarized_dark)

    assert {:noreply, updated} = cycle_theme(%{"key" => "F3"}, term)
    assert updated.assigns.breeze.theme.name == :system16
    assert updated.theme.mode == :system16
  end

  test "rendering exposes theme metadata in the Breeze assigns namespace" do
    session = Breeze.Test.start!(BreezeAssignsView, theme: Breeze.Theme.builtin(:gruvbox))

    assert Breeze.Test.render!(session) =~ "gruvbox-dark/custom/ready"

    Breeze.Test.stop(session)
  end
end
