defmodule Breeze.ViewTest do
  use ExUnit.Case, async: true

  import Breeze.View

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
end
