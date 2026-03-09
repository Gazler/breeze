defmodule Breeze.FocusTest do
  use ExUnit.Case, async: true

  alias Breeze.Focus

  describe "normalize_focus/4" do
    test "trapped scopes prefer default focus over remembered focus" do
      focusables = ["confirm", "dismiss"]

      focus_meta = %{
        "modal" => %{
          id: "modal",
          implicit_owner: nil,
          default_focus: false,
          focus_scope: :trap,
          scope_path: []
        },
        "confirm" => %{
          id: "confirm",
          implicit_owner: "modal",
          default_focus: true,
          focus_scope: nil,
          scope_path: ["modal"]
        },
        "dismiss" => %{
          id: "dismiss",
          implicit_owner: "modal",
          default_focus: false,
          focus_scope: nil,
          scope_path: ["modal"]
        }
      }

      focus_memory = %{"modal" => "dismiss"}

      assert Focus.normalize_focus(nil, focusables, focus_meta, focus_memory) == "confirm"
    end

    test "non-trapped scopes still restore remembered focus first" do
      focusables = ["first", "second"]

      focus_meta = %{
        "first" => %{
          id: "first",
          implicit_owner: nil,
          default_focus: true,
          focus_scope: nil,
          scope_path: []
        },
        "second" => %{
          id: "second",
          implicit_owner: nil,
          default_focus: false,
          focus_scope: nil,
          scope_path: []
        }
      }

      focus_memory = %{__root__: "second"}

      assert Focus.normalize_focus(nil, focusables, focus_meta, focus_memory) == "second"
    end
  end
end
